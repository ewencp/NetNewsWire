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
	public var currentSampleTime: AVAudioFramePosition {
		guard engine.attachedNodes.contains(playerNode),
			  let lastRenderTime = playerNode.lastRenderTime,
			  let playerTime = playerNode.playerTime(forNodeTime: lastRenderTime)
		else {
			return seekBaseline
		}
		return seekBaseline + playerTime.sampleTime
	}

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
		}
	}

	public func play() {
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
		playerNode.stop()
		engine.stop()
		engine.reset()
		pendingBuffers.removeAll()
		scheduledBuffers.removeAll()
		format = nil
		seekBaseline = 0
		state = .idle
	}

	public func addObserver(_ observer: AudioBufferPlayerObserver) {
		observers.add(observer)
	}

	public func removeObserver(_ observer: AudioBufferPlayerObserver) {
		observers.remove(observer)
	}

	public func seek(toSampleTime sampleTime: AVAudioFramePosition) {
		// Resolve all known buffers (scheduled + pending) with their start frames.
		var allBuffers: [(buffer: AVAudioPCMBuffer, startFrame: AVAudioFramePosition)] = scheduledBuffers
		var nextStart: AVAudioFramePosition = scheduledBuffers.last
			.map { $0.startFrame + AVAudioFramePosition($0.buffer.frameLength) }
			?? 0
		for pending in pendingBuffers {
			allBuffers.append((pending, nextStart))
			nextStart += AVAudioFramePosition(pending.frameLength)
		}

		// Find the buffer containing `sampleTime`.
		guard let targetIdx = allBuffers.firstIndex(where: { entry in
			let endFrame = entry.startFrame + AVAudioFramePosition(entry.buffer.frameLength)
			return sampleTime >= entry.startFrame && sampleTime < endFrame
		}) else {
			// Target is past the last buffer — set baseline anyway; the consumer
			// may enqueue more buffers later.
			if engine.isRunning { playerNode.stop() }
			scheduledBuffers.removeAll()
			pendingBuffers.removeAll()
			seekBaseline = sampleTime
			return
		}

		let target = allBuffers[targetIdx]
		let intraBufferOffset = sampleTime - target.startFrame

		// Tear down current schedule and set new baseline.
		if engine.isRunning { playerNode.stop() }
		scheduledBuffers.removeAll()
		seekBaseline = sampleTime

		// Move remaining buffers (after targetIdx) into pending for later scheduling.
		let remaining = Array(allBuffers[(targetIdx + 1)...]).map { $0.buffer }
		pendingBuffers = remaining

		if engine.isRunning {
			// Schedule the first buffer (trimmed or whole) directly onto the node,
			// then schedule remaining via schedulePendingBuffers().
			if intraBufferOffset > 0 {
				if let trimmed = makeBufferSegment(target.buffer, fromFrame: AVAudioFrameCount(intraBufferOffset)) {
					scheduledBuffers.append((trimmed, sampleTime))
					playerNode.scheduleBuffer(trimmed, completionCallbackType: .dataPlayedBack) { [weak self] _ in
						Task { @MainActor in
							self?.handleBufferPlayedBack(trimmed)
						}
					}
				} else {
					log.error("Failed to create buffer segment at sampleTime \(sampleTime, privacy: .public); seek will skip the intra-buffer remainder")
				}
			} else {
				scheduledBuffers.append((target.buffer, sampleTime))
				playerNode.scheduleBuffer(target.buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
					Task { @MainActor in
						self?.handleBufferPlayedBack(target.buffer)
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
		while let buffer = pendingBuffers.first {
			pendingBuffers.removeFirst()
			let startFrame: AVAudioFramePosition = scheduledBuffers.last
				.map { $0.startFrame + AVAudioFramePosition($0.buffer.frameLength) }
				?? 0
			scheduledBuffers.append((buffer, startFrame))
			playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
				Task { @MainActor in
					self?.handleBufferPlayedBack(buffer)
				}
			}
		}
	}

	private func handleBufferPlayedBack(_ buffer: AVAudioPCMBuffer) {
		if let idx = scheduledBuffers.firstIndex(where: { $0.buffer === buffer }) {
			scheduledBuffers.remove(at: idx)
		}
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
}
