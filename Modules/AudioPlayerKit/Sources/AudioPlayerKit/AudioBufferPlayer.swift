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
		state = .idle
	}

	public func addObserver(_ observer: AudioBufferPlayerObserver) {
		observers.add(observer)
	}

	public func removeObserver(_ observer: AudioBufferPlayerObserver) {
		observers.remove(observer)
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
}
