import Foundation
@preconcurrency import AVFoundation
import OSLog

/// Plays a stream of PCM `AVAudioPCMBuffer`s via `AVAudioEngine` +
/// `AVAudioPlayerNode`. Owns `AVAudioSession.interruptionNotification` and
/// `AVAudioEngineConfigurationChangeNotification` observers (added in Task 4);
/// recovers from audio session interruption by tearing down and rebuilding
/// the engine (the PocketCasts EffectsPlayer pattern — `AVAudioEngine`
/// doesn't handle interruptions as natively as `AVPlayer`).
///
/// Backend-agnostic: consumers produce PCM (AVSpeechSynthesizer.write,
/// Orpheus vocoder, anything else) and feed buffers via `enqueue(_:)`.
///
/// Concurrency: `@MainActor`. All public API and observer callbacks fire on
/// the main actor. AVAudioEngine callbacks are bounced back to the main
/// actor before touching player state.
@MainActor
public final class AudioBufferPlayer {

	// MARK: - Public state

	public private(set) var state: AudioBufferPlayerState = .idle {
		didSet {
			if state != oldValue {
				notifyStateChanged()
			}
		}
	}

	/// Sample rate of the most-recently-enqueued buffer, in Hz. Returns 0 if
	/// nothing has been enqueued yet.
	public var sampleRate: Double { format?.sampleRate ?? 0 }

	/// Number of audio frames played since the *current article's* start.
	/// Increases monotonically during playback. Reset to a new value on
	/// `seek(toSampleTime:)`. To convert to seconds: `currentSampleTime / sampleRate`.
	///
	/// The origin (frame 0) is defined by the consumer: when the consumer
	/// calls `stop()` and then enqueues a new article's buffers, frame 0 is
	/// the start of that new article. The player itself does not know about
	/// article boundaries — it tracks frames consumed from its current
	/// buffer-queue origin.
	///
	/// While `playerNode` is rendering, the live value is computed from
	/// `playerNode.lastRenderTime + playerTime.sampleTime` and cached. When
	/// the node is paused (or briefly between stop/play), `lastRenderTime`
	/// returns nil; we then return the cache rather than `seekBaseline`, so
	/// the elapsed position survives a pause instead of snapping back to
	/// the last seek origin.
	public var currentSampleTime: AVAudioFramePosition {
		if engine.attachedNodes.contains(playerNode),
		   let lastRenderTime = playerNode.lastRenderTime,
		   let playerTime = playerNode.playerTime(forNodeTime: lastRenderTime) {
			lastObservedSampleTime = seekBaseline + playerTime.sampleTime
		}
		return lastObservedSampleTime
	}

	/// Cached observation of the most recent live `currentSampleTime`. Used
	/// to keep elapsed-time queries stable across pause and brief
	/// stop/play transitions when `playerNode.lastRenderTime` is nil.
	private var lastObservedSampleTime: AVAudioFramePosition = 0

	// MARK: - Private state

	private let engine = AVAudioEngine()
	private let playerNode = AVAudioPlayerNode()
	private var format: AVAudioFormat?

	/// FIFO of buffers yet to be scheduled on the player node. Buffers move
	/// from this queue into the player node's internal schedule via
	/// `scheduleBuffer`.
	private var pendingBuffers: [AVAudioPCMBuffer] = []

	/// Buffers that have been scheduled on the player node, in order. Used
	/// for seek + interruption recovery in later tasks.
	private var scheduledBuffers: [(buffer: AVAudioPCMBuffer, startFrame: AVAudioFramePosition)] = []

	/// Frame offset added to `playerNode.playerTime`'s `sampleTime` to express
	/// "frames since article start" rather than "frames since last play/seek."
	/// Updated on `seek(toSampleTime:)` and on `stop()`.
	private var seekBaseline: AVAudioFramePosition = 0

	/// Monotonic version tag bumped on every queue-clearing operation
	/// (`resetQueue`, `seek`, `stop`). Each `scheduleBuffer` call captures
	/// the current generation; the completion callback checks that its
	/// generation matches before mutating tracking state. This prevents
	/// stale completion callbacks (fired by `playerNode.stop()` cancelling
	/// in-flight buffers) from spuriously removing entries that were
	/// just re-scheduled — a real hazard because the same
	/// `AVAudioPCMBuffer` instances are re-enqueued by `resetQueue`,
	/// so object-identity-based de-duplication is insufficient.
	private var schedulingGeneration: UInt64 = 0

	private let observers = NSHashTable<AnyObject>.weakObjects()

	private let log = Logger(subsystem: "io.ewencp.netnewswire.AudioPlayerKit", category: "AudioBufferPlayer")

	// MARK: - Initialization

	public init() {
		// Engine attachment happens lazily on first play() so we don't hold
		// an active audio session before the consumer is ready.
	}

	// MARK: - Public API

	public func enqueue(_ buffer: AVAudioPCMBuffer) {
		if format == nil {
			format = buffer.format
		} else if format != buffer.format {
			log.warning("Buffer format \(buffer.format, privacy: .public) does not match player format; ignoring")
			return
		}
		pendingBuffers.append(buffer)
		// Schedule immediately if the engine is running (including paused state — node-paused
		// keeps the engine running so newly enqueued buffers can be queued for resume).
		// Pre-play enqueues are scheduled when play() starts the engine.
		if engine.isRunning {
			schedulePendingBuffers()
			// Recover from .finished: if we transitioned to .finished due to a
			// brief queue underflow (e.g., between speech blocks of a multi-
			// block utterance), restart playback now that more buffers are
			// available. .paused stays .paused — the user explicitly paused,
			// so don't auto-resume.
			if state == .finished {
				playerNode.play()
				state = .playing
			}
		}
	}

	public func play() {
		startObservingNotifications()
		guard format != nil else {
			// Nothing enqueued yet — first enqueue will trigger scheduling
			// and the next play() can start the engine.
			state = .preparing
			return
		}
		do {
			try ensureEngineRunning()
			schedulePendingBuffers()
			playerNode.play()
			state = scheduledBuffers.isEmpty && pendingBuffers.isEmpty ? .finished : .playing
		} catch {
			log.error("Failed to start engine: \(error.localizedDescription, privacy: .public)")
			state = .idle
		}
	}

	public func pause() {
		guard state == .playing else { return }
		playerNode.pause()
		state = .paused
	}

	public func stop() {
		schedulingGeneration &+= 1
		playerNode.stop()
		engine.stop()
		engine.reset()
		pendingBuffers.removeAll()
		scheduledBuffers.removeAll()
		format = nil
		seekBaseline = 0
		lastObservedSampleTime = 0
		#if os(iOS)
		wasPlayingBeforeInterruption = false
		#endif
		state = .idle
	}

	public func addObserver(_ observer: AudioBufferPlayerObserver) {
		observers.add(observer)
	}

	public func removeObserver(_ observer: AudioBufferPlayerObserver) {
		observers.remove(observer)
	}

	/// Atomically replace the playback queue with the given buffers, treating
	/// the first buffer as being at `sampleTime` in the consumer's article-frame
	/// coordinate space. Existing buffers in scheduledBuffers/pendingBuffers
	/// are discarded.
	///
	/// Use this when the consumer wants to seek to content the player no
	/// longer has in its queue (e.g., skip-backward to a block whose buffers
	/// have already played out, but the consumer retained them in its own
	/// cache). Unlike `seek(toSampleTime:)`, which searches the current queue
	/// for the target frame, `resetQueue` lets the consumer hand the player a
	/// fresh queue rooted at any sample-time.
	///
	/// Format is preserved (must match the current format if one is set).
	/// State is unchanged — the consumer typically follows this with
	/// `play()` to resume.
	public func resetQueue(with buffers: [AVAudioPCMBuffer], startingAtSampleTime sampleTime: AVAudioFramePosition) {
		// Bump generation BEFORE clearing — completions from canceled buffers
		// fire after `playerNode.stop()` and check generation to reject
		// stale callbacks. Required because consumers may re-enqueue the same
		// `AVAudioPCMBuffer` instances they had before (e.g., from a retained
		// rendering cache), so the canceled completion's identity-based
		// lookup would otherwise match the freshly-rescheduled buffer.
		schedulingGeneration &+= 1
		if engine.isRunning {
			playerNode.stop()
		}
		scheduledBuffers.removeAll()
		pendingBuffers = buffers
		seekBaseline = sampleTime
		lastObservedSampleTime = sampleTime
		// Establish format from the first buffer if not already set.
		if format == nil, let first = buffers.first {
			format = first.format
		}
		if engine.isRunning {
			schedulePendingBuffers()
		}
	}

	public func seek(toSampleTime sampleTime: AVAudioFramePosition) {
		// `sampleTime` is in the consumer's article-frame coordinate (same
		// basis as `seekBaseline`). Buffers in `scheduledBuffers`/`pendingBuffers`
		// carry queue-relative `startFrame` values (always starting at 0 for
		// the first scheduled buffer after a fresh `resetQueue`/`seek`).
		// Translate before searching.
		let queueRelative = sampleTime - seekBaseline

		// Resolve all known buffers (scheduled + pending) with their start frames.
		var allBuffers: [(buffer: AVAudioPCMBuffer, startFrame: AVAudioFramePosition)] = scheduledBuffers
		var nextStart: AVAudioFramePosition = scheduledBuffers.last
			.map { $0.startFrame + AVAudioFramePosition($0.buffer.frameLength) }
			?? 0
		for pending in pendingBuffers {
			allBuffers.append((pending, nextStart))
			nextStart += AVAudioFramePosition(pending.frameLength)
		}

		// Find the buffer containing `queueRelative`.
		guard let targetIdx = allBuffers.firstIndex(where: { entry in
			let endFrame = entry.startFrame + AVAudioFramePosition(entry.buffer.frameLength)
			return queueRelative >= entry.startFrame && queueRelative < endFrame
		}) else {
			// Target is past the last buffer (or before the first if
			// `queueRelative` is negative) — set baseline anyway; the consumer
			// may enqueue more buffers later.
			schedulingGeneration &+= 1
			if engine.isRunning { playerNode.stop() }
			scheduledBuffers.removeAll()
			pendingBuffers.removeAll()
			seekBaseline = sampleTime
			lastObservedSampleTime = sampleTime
			return
		}

		let target = allBuffers[targetIdx]
		let intraBufferOffset = queueRelative - target.startFrame

		// Bump generation BEFORE clearing — completions from canceled buffers
		// fire after `playerNode.stop()` and check generation to reject
		// stale callbacks.
		schedulingGeneration &+= 1
		if engine.isRunning { playerNode.stop() }
		scheduledBuffers.removeAll()
		seekBaseline = sampleTime
		lastObservedSampleTime = sampleTime

		// Move remaining buffers (after targetIdx) into pending for later scheduling.
		let remaining = Array(allBuffers[(targetIdx + 1)...]).map { $0.buffer }
		pendingBuffers = remaining

		if engine.isRunning {
			let gen = schedulingGeneration
			// Schedule the first buffer (trimmed or whole) directly onto the node,
			// then schedule remaining via schedulePendingBuffers(). Stored
			// `startFrame` is queue-relative (0 — first in the fresh queue).
			if intraBufferOffset > 0 {
				if let trimmed = makeBufferSegment(target.buffer, fromFrame: AVAudioFrameCount(intraBufferOffset)) {
					scheduledBuffers.append((trimmed, 0))
					playerNode.scheduleBuffer(trimmed, completionCallbackType: .dataPlayedBack) { [weak self] _ in
						Task { @MainActor in
							self?.handleBufferPlayedBack(trimmed, scheduledUnderGeneration: gen)
						}
					}
				} else {
					log.error("Failed to create buffer segment at sampleTime \(sampleTime, privacy: .public); seek will skip the intra-buffer remainder")
				}
			} else {
				scheduledBuffers.append((target.buffer, 0))
				playerNode.scheduleBuffer(target.buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
					Task { @MainActor in
						self?.handleBufferPlayedBack(target.buffer, scheduledUnderGeneration: gen)
					}
				}
			}
			schedulePendingBuffers()

			// Preserve playing state across the seek.
			if state == .playing {
				playerNode.play()
			}
		} else {
			// Engine not running: record the first buffer as pending so play()
			// will enqueue it when the engine starts. Trimming is applied here
			// so the correct portion is played from the seek point.
			if intraBufferOffset > 0 {
				// Known limitation: when this pre-play seek path runs, the trimmed buffer
				// ends up in pendingBuffers without a startFrame record. When play() later
				// calls schedulePendingBuffers(), it assigns startFrame=0 (because
				// scheduledBuffers is empty), not startFrame=sampleTime. A subsequent
				// seek while playing would then reconstruct allBuffers with the wrong
				// startFrame for this buffer, causing an incorrect intra-buffer offset
				// calculation (audio position would be off by sampleTime frames).
				// Triggered only by seek-before-first-play followed by a second seek
				// after play starts — a pre-play-scrubbing edge case T6 will not hit
				// in normal use. Fix candidate: thread a seekBaseline-aware startFrame
				// assignment through schedulePendingBuffers when wired up in T9.
				if let trimmed = makeBufferSegment(target.buffer, fromFrame: AVAudioFrameCount(intraBufferOffset)) {
					pendingBuffers.insert(trimmed, at: 0)
				}
			} else {
				pendingBuffers.insert(target.buffer, at: 0)
			}
		}
	}

	// MARK: - Private

	private func ensureEngineRunning() throws {
		guard let format else {
			return
		}

		if !engine.attachedNodes.contains(playerNode) {
			engine.attach(playerNode)
			engine.connect(playerNode, to: engine.mainMixerNode, format: format)
		}
		if !engine.isRunning {
			try engine.start()
		}
	}

	private func schedulePendingBuffers() {
		let gen = schedulingGeneration
		while let buffer = pendingBuffers.first {
			pendingBuffers.removeFirst()
			let startFrame: AVAudioFramePosition = scheduledBuffers.last
				.map { $0.startFrame + AVAudioFramePosition($0.buffer.frameLength) }
				?? 0
			scheduledBuffers.append((buffer, startFrame))
			playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
				Task { @MainActor in
					self?.handleBufferPlayedBack(buffer, scheduledUnderGeneration: gen)
				}
			}
		}
	}

	private func handleBufferPlayedBack(_ buffer: AVAudioPCMBuffer, scheduledUnderGeneration gen: UInt64) {
		// Reject stale completions: if the queue has been cleared/rebuilt
		// since this buffer was scheduled, this callback is from the
		// previous generation (fired by `playerNode.stop()` cancelling the
		// old schedule) and must not touch the current scheduling state.
		// Without this, the same `AVAudioPCMBuffer` instance re-enqueued
		// via `resetQueue` (legitimately, with a fresh completion of its
		// own) would be matched by the canceled completion's lookup and
		// spuriously removed before the buffer has actually played —
		// causing premature block-advance dispatch and lost real
		// completion-tracking afterward.
		guard gen == schedulingGeneration else {
			return
		}
		guard let idx = scheduledBuffers.firstIndex(where: { $0.buffer === buffer }) else {
			return
		}
		scheduledBuffers.remove(at: idx)
		notifyDidAdvance()
		if scheduledBuffers.isEmpty && pendingBuffers.isEmpty {
			state = .finished
		}
	}

	private func notifyStateChanged() {
		let snapshot = state
		for case let observer as AudioBufferPlayerObserver in observers.allObjects {
			observer.audioBufferPlayer(self, didChangeState: snapshot)
		}
	}

	/// Notify observers of a sample-time advance. Fires at buffer-completion
	/// granularity (each scheduled buffer's `.dataPlayedBack` callback).
	/// Sufficient for block-boundary detection in `AppleSpeechSynth`; finer
	/// granularity (e.g., for smooth scrubbing position display) would need a
	/// timer or display-link dispatch.
	private func notifyDidAdvance() {
		let snapshot = currentSampleTime
		for case let observer as AudioBufferPlayerObserver in observers.allObjects {
			observer.audioBufferPlayer(self, didAdvanceTo: snapshot)
		}
	}

	private func makeBufferSegment(_ source: AVAudioPCMBuffer, fromFrame: AVAudioFrameCount) -> AVAudioPCMBuffer? {
		guard fromFrame < source.frameLength else { return nil }
		let segmentLength = source.frameLength - fromFrame
		guard segmentLength > 0,
			  let segment = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: segmentLength)
		else {
			return nil
		}
		segment.frameLength = segmentLength
		guard let srcData = source.floatChannelData, let dstData = segment.floatChannelData else {
			return nil
		}
		let channelCount = Int(source.format.channelCount)
		for channel in 0..<channelCount {
			let srcPtr = srcData[channel].advanced(by: Int(fromFrame))
			let dstPtr = dstData[channel]
			dstPtr.update(from: srcPtr, count: Int(segmentLength))
		}
		return segment
	}

	// MARK: - Interruption (iOS only)

#if os(iOS)

	/// Set on `.began` if the player was playing or preparing. Used to decide
	/// whether to auto-resume after `.ended` with `.shouldResume`.
	private var wasPlayingBeforeInterruption: Bool = false

	private var interruptionObservationToken: NSObjectProtocol?
	private var configurationChangeToken: NSObjectProtocol?

	private func startObservingNotifications() {
		guard interruptionObservationToken == nil else { return }

		interruptionObservationToken = NotificationCenter.default.addObserver(
			forName: AVAudioSession.interruptionNotification,
			object: nil,
			queue: nil
		) { [weak self] notification in
			// Notification posts on a background queue. Extract Sendable
			// primitives, then hop to MainActor.
			guard let info = notification.userInfo,
				  let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt else {
				return
			}
			let optionsRaw = (info[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
			Task { @MainActor in
				self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
			}
		}

		configurationChangeToken = NotificationCenter.default.addObserver(
			forName: .AVAudioEngineConfigurationChange,
			object: engine,
			queue: nil
		) { [weak self] _ in
			Task { @MainActor in
				self?.handleConfigurationChange()
			}
		}
	}

	private func handleInterruption(typeRaw: UInt, optionsRaw: UInt) {
		guard let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
		let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
		let action = InterruptionDecision.decide(
			type: type,
			options: options,
			currentState: state,
			wasPlayingBeforeInterruption: wasPlayingBeforeInterruption
		)
		apply(interruptionAction: action)
	}

	private func apply(interruptionAction action: InterruptionAction) {
		switch action {
		case .ignore:
			return

		case .beginInterruption(let rememberToResume):
			wasPlayingBeforeInterruption = rememberToResume
			state = .interrupted

		case .attemptResume:
			// Reactivate the audio session, then restart the engine.
			// These are separated deliberately because the two
			// operations have different failure semantics:
			//
			// - On a real iOS device coming out of a real interruption,
			//   the system has deactivated our session at .began and
			//   may or may not reactivate it before .ended fires.
			//   Calling setActive(true) here reactivates if needed and
			//   is a no-op otherwise. If a different app still holds
			//   the session, setActive can throw — in which case
			//   ensureEngineRunning() will also fail (engine can't
			//   start without an active session), and we fall back to
			//   .interrupted.
			//
			// - In a headless simulator test that synthesizes an
			//   interruption notification, the session was never
			//   actually deactivated and the engine kept running.
			//   setActive(true) can still throw a simulator-specific
			//   error, but the engine restart is a no-op (it was never
			//   stopped) and playback resumes correctly. Treating
			//   setActive failure as best-effort keeps this path
			//   working.
			do {
				try AVAudioSession.sharedInstance().setActive(true)
			} catch {
				log.warning("AVAudioSession.setActive(true) on interruption end failed: \(error.localizedDescription, privacy: .public). Continuing with engine restart; session may already be active.")
			}

			do {
				try ensureEngineRunning()
				// Don't reschedule here. Per Apple FW Engineer (forum
				// 663604): engine teardown-recovery belongs in
				// AVAudioEngineConfigurationChangeNotification, not in
				// the .ended handler. If the system actually tore the
				// engine down, `handleConfigurationChange` will fire and
				// handle the rebuild + reschedule. If the engine kept
				// running (simulator case, or quick interruption that
				// didn't trigger teardown), the scheduled buffers are
				// still on the player node and resume picks up where it
				// left off.
				playerNode.play()
				state = scheduledBuffers.isEmpty && pendingBuffers.isEmpty ? .finished : .playing
			} catch {
				log.error("Engine restart after interruption failed: \(error.localizedDescription, privacy: .public)")
				state = .interrupted
			}
			wasPlayingBeforeInterruption = false

		case .acknowledgeEnd:
			wasPlayingBeforeInterruption = false
		}
	}

	private func handleConfigurationChange() {
		// Engine configuration change can fire after the audio session is
		// re-activated post-interruption, or when audio routes change. If we
		// expected to be playing, restart the engine and reschedule from
		// saved position.
		guard wasPlayingBeforeInterruption || state == .playing else { return }
		do {
			try ensureEngineRunning()
			rescheduleAfterEngineRebuild()
			playerNode.play()
		} catch {
			log.error("Failed to restart engine after configuration change: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// On engine teardown/restart, the player node loses its scheduled
	/// buffers. Re-schedule what was scheduled, picking up from the current
	/// sample-time baseline.
	private func rescheduleAfterEngineRebuild() {
		let currentScheduled = scheduledBuffers
		scheduledBuffers.removeAll()
		pendingBuffers.insert(contentsOf: currentScheduled.map(\.buffer), at: 0)
		schedulePendingBuffers()
	}

#else

	private var wasPlayingBeforeInterruption: Bool { false }

	private func startObservingNotifications() {}

#endif
}
