import Foundation
import AVFoundation
import ArticleSpeech
import AudioPlayerKit
import OSLog

/// Plays a sequence of `SpeechBlock`s by rendering each block's text to PCM
/// via `AVSpeechSynthesizer.write(_:toBufferCallback:)` and feeding the
/// buffers to an `AudioBufferPlayer`. AVSpeechSynthesizer's built-in
/// playback is bypassed entirely — `write` is used purely as a PCM source.
///
/// Maintains a retain-2 + prefetch-2 rendering window around the current
/// block: previous 2 blocks' buffers retained for fast skip-back; next 2
/// blocks rendered ahead for gap-free playback and fast skip-forward.
///
/// State transitions are driven by `AudioBufferPlayer` via the
/// `AudioBufferPlayerObserver` protocol; block-advance is detected by
/// observing sample-time crossings of rendered-block start positions.
@MainActor
public final class AppleSpeechSynth: SpeechSynth {

	// MARK: - Public state

	public private(set) var state: SpeechSynthState = .idle {
		didSet {
			if state != oldValue {
				notifyObservers()
			}
		}
	}

	public var isAvailable: Bool { get async { true } }

	public func availableVoices() async -> [SpeechVoice] {
		var combined = AppleSpeechVoiceCatalog.installedVoices(matching: AppleSpeechVoiceCatalog.primaryLanguageTag)
		let installedIDs = Set(combined.map(\.identifier))
		let recommended = AppleSpeechVoiceCatalog.recommendedVoices(matching: AppleSpeechVoiceCatalog.primaryLanguageTag)
			.filter { !installedIDs.contains($0.identifier) }
		combined.append(contentsOf: recommended)
		return combined
	}

	public var durationSeconds: Double {
		guard player.sampleRate > 0 else { return 0 }
		// Use actual rendered totalFrames when available; fall back to a
		// text-length-based estimate only for blocks not yet rendered.
		// As the article plays through, all blocks get rendered and the
		// duration converges to the true playback time.
		let totalFrames = blocks.indices.reduce(AVAudioFramePosition(0)) { acc, idx in
			let frames = renderedBlocks[idx]?.totalFrames ?? estimateBlockFrames(at: idx)
			return acc + frames
		}
		return Double(totalFrames) / player.sampleRate
	}

	public var elapsedSeconds: Double {
		guard player.sampleRate > 0 else { return 0 }
		return Double(player.currentSampleTime) / player.sampleRate
	}

	// MARK: - Private state

	private let synth = AVSpeechSynthesizer()
	private let player = AudioBufferPlayer()
	private let observers = NSHashTable<AnyObject>.weakObjects()

	private var blocks: [SpeechBlock] = []
	private var voice: SpeechVoice?
	private var rateMultiplier: Float = 1.0
	private var currentBlockIndex: Int = 0

	private var renderedBlocks: [Int: RenderedBlock] = [:]
	private var renderingTask: Task<Void, Never>?

	/// Monotonic version tag bumped on every operation that invalidates
	/// in-flight rendering (`play(blocks:...)`, `stop()`, `seek` paths).
	/// `renderBlock` captures the current epoch at entry; the `synth.write`
	/// buffer callbacks check the epoch before enqueueing on the player.
	/// This is necessary because `synth.write` callbacks run independently
	/// of our Swift `Task` cancellation — they keep firing for the
	/// remainder of the utterance even after `renderingTask?.cancel()`,
	/// and would otherwise append buffers from the canceled block onto
	/// the freshly-rebuilt player queue.
	private var renderEpoch: UInt64 = 0

	/// Highest block index whose buffers have been enqueued on the player.
	/// Tracks the player-queue watermark independently of `renderedBlocks`
	/// (which is the in-memory buffer cache). After a seek's `resetQueue`,
	/// only [target, lastEnqueuedBlockIndex] are in the player's queue;
	/// `topUpPlayerQueue()` extends this as `currentBlockIndex` advances
	/// and brings further already-rendered blocks back into the queue.
	private var lastEnqueuedBlockIndex: Int = -1

	private let retainBack: Int = 2
	private let prefetchAhead: Int = 2

	private let log = Logger(subsystem: "io.ewencp.netnewswire.AppleSpeechKit", category: "AppleSpeechSynth")

	// MARK: - Initialization

	public init() {
		player.addObserver(self)
	}

	// MARK: - SpeechSynth conformance

	public func play(blocks: [SpeechBlock], voice: SpeechVoice, rate: Float, startingAt: Int) {
		renderEpoch &+= 1
		renderingTask?.cancel()
		renderingTask = nil
		player.stop()
		renderedBlocks.removeAll()
		lastEnqueuedBlockIndex = -1

		self.blocks = blocks
		self.voice = voice
		self.rateMultiplier = rate

		let safeStart = max(0, min(startingAt, max(0, blocks.count - 1)))
		currentBlockIndex = safeStart

		guard !blocks.isEmpty else {
			state = .idle
			return
		}

		state = .preparing
		activateAudioSessionIfNeeded()
		ensureRenderingProgresses()
	}

	public func pause() {
		player.pause()
	}

	public func resume() {
		// Re-activate the audio session before continuing. Required after an
		// AVAudioSession interruption (e.g., Apple Music takeover) deactivated
		// the session — without this, playback can stutter briefly before iOS
		// kills the engine. Mirrors `play()`'s session lifecycle; no-op on macOS.
		activateAudioSessionIfNeeded()
		player.play()
	}

	public func stop() {
		renderEpoch &+= 1
		renderingTask?.cancel()
		renderingTask = nil
		player.stop()
		renderedBlocks.removeAll()
		lastEnqueuedBlockIndex = -1
		blocks = []
		currentBlockIndex = 0
		state = .idle
		deactivateAudioSession()
	}

	public func skipForward() {
		guard !blocks.isEmpty else { return }
		seek(toBlockIndex: min(currentBlockIndex + 1, blocks.count - 1))
	}

	public func skipBackward() {
		guard !blocks.isEmpty else { return }
		seek(toBlockIndex: max(currentBlockIndex - 1, 0))
	}

	public func seek(toSeconds seconds: Double) {
		guard player.sampleRate > 0, !blocks.isEmpty else { return }
		let targetFrame = AVAudioFramePosition(seconds * player.sampleRate)
		let targetBlock = blockIndex(forSampleTime: targetFrame) ?? 0
		let blockStart = renderedBlocks[targetBlock]?.startSampleTime ?? 0
		seek(toBlockIndex: targetBlock, withinBlockSampleOffset: targetFrame - blockStart)
	}

	public func addObserver(_ observer: SpeechSynthObserver) {
		observers.add(observer)
	}

	public func removeObserver(_ observer: SpeechSynthObserver) {
		observers.remove(observer)
	}

	// MARK: - Block-boundary lookup (internal — for tests and seek)

	internal func blockBoundarySampleTime(forBlockIndex index: Int) -> AVAudioFramePosition? {
		renderedBlocks[index]?.startSampleTime
	}

	internal func blockIndex(forSampleTime sampleTime: AVAudioFramePosition) -> Int? {
		// Find the highest index whose startSampleTime <= sampleTime.
		let sorted = renderedBlocks.sorted { $0.key < $1.key }
		return sorted.last(where: { $0.value.startSampleTime <= sampleTime })?.key
	}

	// MARK: - Rendering window

	private func seek(toBlockIndex targetIndex: Int, withinBlockSampleOffset offset: AVAudioFramePosition = 0) {
		let bounded = max(0, min(targetIndex, blocks.count - 1))
		// Use case-pattern matching rather than value equality: the state's
		// stored blockIndex/totalBlocks may be slightly stale relative to
		// currentBlockIndex (e.g., during a transient that occurred between
		// didAdvanceTo updating currentBlockIndex and propagating state).
		let wasPlaying: Bool
		if case .speaking = state { wasPlaying = true } else { wasPlaying = false }
		currentBlockIndex = bounded

		// Cancel any in-flight rendering — it may be on a block that's no
		// longer near our window. Bump renderEpoch so that synth.write
		// callbacks still firing for the canceled render won't enqueue
		// their buffers on the freshly-rebuilt player queue.
		// `ensureRenderingProgresses` below picks up the right next target
		// for the new currentBlockIndex.
		renderEpoch &+= 1
		renderingTask?.cancel()
		renderingTask = nil

		evictOutOfWindow()

		if let targetBlock = renderedBlocks[bounded] {
			// Target already rendered: rebuild the player's queue from
			// renderedBlocks starting at the target. Enqueue only the
			// contiguous run of rendered blocks from `bounded` forward —
			// `topUpPlayerQueue` will pick up further blocks as the window
			// slides and renders complete.
			let upperBound = min(bounded + prefetchAhead, blocks.count - 1)
			var contiguousBuffers: [AVAudioPCMBuffer] = []
			var lastIncluded = bounded - 1
			for i in bounded...upperBound {
				guard let rb = renderedBlocks[i] else { break }
				contiguousBuffers.append(contentsOf: rb.buffers)
				lastIncluded = i
			}
			player.resetQueue(with: contiguousBuffers, startingAtSampleTime: targetBlock.startSampleTime)
			lastEnqueuedBlockIndex = lastIncluded

			// Update state immediately to reflect the new blockIndex.
			// `player.state` didn't change values (stayed `.playing`), so
			// the player's didChangeState observer chain won't fire here —
			// without this explicit update, observers (and the UI's
			// progress bar) wouldn't see the position change until the
			// next buffer completion's didAdvanceTo arrives mid-block.
			switch state {
			case .speaking:
				state = .speaking(blockIndex: bounded, totalBlocks: blocks.count)
			case .paused:
				state = .paused(blockIndex: bounded, totalBlocks: blocks.count)
			default:
				break
			}

			if offset > 0 {
				// Intra-block offset: now that the queue is rebuilt and the
				// target block's buffers are scheduled, `player.seek` can
				// find the offset within them.
				player.seek(toSampleTime: targetBlock.startSampleTime + offset)
			}

			if wasPlaying {
				player.play()
			}

			// Kick rendering for anything in window that's still missing.
			ensureRenderingProgresses()
		} else {
			// Target not yet rendered: clear the player's stale queue, kick
			// off priority render. Post-render callback in
			// `ensureRenderingProgresses` will seek+play when buffers
			// arrive.
			state = .preparing
			player.resetQueue(with: [], startingAtSampleTime: 0)
			lastEnqueuedBlockIndex = bounded - 1
			ensureRenderingProgresses(priorityBlock: bounded, postRenderSeekOffset: offset, postRenderPlay: wasPlaying)
		}
	}

	/// Extends the player's queue forward by enqueueing buffers of any
	/// already-rendered blocks in the prefetch window that aren't yet in
	/// the queue. Idempotent — uses `lastEnqueuedBlockIndex` as the
	/// watermark.
	///
	/// Called after `seek` (to catch additional rendered blocks the
	/// resetQueue didn't include), after each `didAdvanceTo` (to extend
	/// the queue as the window slides), and after each `renderBlock`
	/// completion (in case the freshly-rendered block fills a gap).
	private func topUpPlayerQueue() {
		let upperBound = min(currentBlockIndex + prefetchAhead, blocks.count - 1)
		while lastEnqueuedBlockIndex < upperBound {
			let next = lastEnqueuedBlockIndex + 1
			guard next >= 0, next < blocks.count, let rb = renderedBlocks[next] else { break }
			for buf in rb.buffers {
				player.enqueue(buf)
			}
			lastEnqueuedBlockIndex = next
		}
	}

	private func evictOutOfWindow() {
		guard !blocks.isEmpty else {
			renderedBlocks.removeAll()
			return
		}
		// Mid-article eviction is disabled. Each `RenderedBlock`'s
		// `startSampleTime` is computed as `prior.startSampleTime +
		// prior.totalFrames`; if we evict block M and later re-render it
		// when block M-1 isn't in `renderedBlocks`, the re-render falls
		// back to `estimateBlockFrames` (text-length heuristic) and drifts
		// from the originally-chained value. `blockIndex(forSampleTime:)`
		// then returns wrong indices across the formerly-evicted boundary,
		// which breaks `currentBlockIndex` tracking and cascades to wrong
		// `shouldEnqueue` decisions on forward renders.
		//
		// Memory cost: ~1MB per block at 22kHz mono. Bounded by the
		// article size; acceptable for a single-article playback session.
		// `play(blocks:...)` and `stop()` clear `renderedBlocks` for
		// article boundaries.
		//
		// retainBack/prefetchAhead still bound `ensureRenderingProgresses`'s
		// proactive-rendering window, just not the in-memory cache.
	}

	private func ensureRenderingProgresses(
		priorityBlock: Int? = nil,
		postRenderSeekOffset: AVAudioFramePosition = 0,
		postRenderPlay: Bool = false
	) {
		guard renderingTask == nil else { return }
		guard let voice else { return }
		guard !blocks.isEmpty else { return }

		let lo = max(0, currentBlockIndex - retainBack)
		let hi = min(blocks.count - 1, currentBlockIndex + prefetchAhead)

		let target: Int? = {
			if let priority = priorityBlock, renderedBlocks[priority] == nil {
				return priority
			}
			// Current block first (so playback can start ASAP).
			if renderedBlocks[currentBlockIndex] == nil { return currentBlockIndex }
			// Then forward prefetch in order.
			if currentBlockIndex + 1 <= hi {
				for idx in (currentBlockIndex + 1)...hi {
					if renderedBlocks[idx] == nil { return idx }
				}
			}
			// Then backward retention (skip-back support).
			if currentBlockIndex - 1 >= lo {
				for idx in stride(from: currentBlockIndex - 1, through: lo, by: -1) {
					if renderedBlocks[idx] == nil { return idx }
				}
			}
			return nil
		}()

		guard let nextTarget = target else { return }

		let myEpoch = renderEpoch
		renderingTask = Task { @MainActor [weak self] in
			await self?.renderBlock(at: nextTarget, voice: voice)

			// Stale-task guard: if the epoch changed during the await, a
			// newer seek/play has already set up its own rendering plan and
			// its own `renderingTask`. Return without clobbering that
			// reference and without applying our stale priorityBlock/seek
			// instructions or recursing into `ensureRenderingProgresses`.
			guard self?.renderEpoch == myEpoch else { return }

			self?.renderingTask = nil

			if priorityBlock == nextTarget,
			   let block = self?.renderedBlocks[nextTarget] {
				self?.player.seek(toSampleTime: block.startSampleTime + postRenderSeekOffset)
				if postRenderPlay { self?.player.play() }
			}

			self?.ensureRenderingProgresses()
		}
	}

	private func renderBlock(at index: Int, voice: SpeechVoice) async {
		guard index < blocks.count else { return }
		let block = blocks[index]
		let utterance = makeUtterance(from: block, voice: voice)
		// Capture renderEpoch at entry. Buffer callbacks check it so that
		// in-flight callbacks from a render that's since been canceled
		// don't enqueue stale buffers on the player.
		let myEpoch = renderEpoch
		// Capture the should-enqueue decision at entry. The decision is
		// "is this block at or ahead of where playback currently is?" —
		// backward-retention renders (index < currentBlockIndex) skip the
		// player enqueue so their buffers don't appear in the play queue
		// after current forward content. Captured ONCE at entry rather
		// than per-callback so the decision is consistent for the whole
		// render even if `currentBlockIndex` advances during render.
		let shouldEnqueueThisRender = index >= currentBlockIndex

		// Compute startSampleTime relative to prior blocks. If the prior block
		// is rendered, use its true end; otherwise estimate from text length.
		let startSampleTime: AVAudioFramePosition
		if index == 0 {
			startSampleTime = 0
		} else if let prior = renderedBlocks[index - 1] {
			startSampleTime = prior.startSampleTime + prior.totalFrames
		} else {
			startSampleTime = (0..<index).reduce(AVAudioFramePosition(0)) { $0 + estimateBlockFrames(at: $1) }
		}

		// Holder for write-callback-mutated state. The callback may run on a
		// background thread (and we hop to MainActor inside), so we wrap mutable
		// state in a reference type rather than capturing locals by-reference.
		final class CollectionState: @unchecked Sendable {
			var collectedBuffers: [AVAudioPCMBuffer] = []  // MainActor-only
			var totalFrames: AVAudioFramePosition = 0       // MainActor-only
			var resumed = false                             // MainActor-only
		}
		let collection = CollectionState()
		let preDelay = block.kind.preUtteranceDelay
		let postDelay = block.kind.postUtteranceDelay

		await withCheckedContinuation { continuation in
			synth.write(utterance) { [weak self] buffer in
				guard let pcm = buffer as? AVAudioPCMBuffer else { return }
				if pcm.frameLength == 0 {
					// End-of-utterance signal. AVSpeechSynthesizer.write can
					// fire this callback multiple times; guard against
					// double-resume which would crash CheckedContinuation.
					Task { @MainActor in
						if collection.resumed { return }
						collection.resumed = true
						guard let self = self, self.renderEpoch == myEpoch else {
							continuation.resume()
							return
						}
						if let template = collection.collectedBuffers.first,
						   let silence = self.makeSilenceBuffer(seconds: postDelay, basedOn: template) {
							collection.collectedBuffers.append(silence)
							collection.totalFrames += AVAudioFramePosition(silence.frameLength)
							if shouldEnqueueThisRender { self.player.enqueue(silence) }
						}
						continuation.resume()
					}
					return
				}
				let reinterpreted = self?.reinterpret(pcm) ?? pcm
				Task { @MainActor in
					if collection.resumed { return }
					// Stale-render guard: skip both player enqueue and local
					// collection if our epoch is stale (render was canceled).
					guard let self = self, self.renderEpoch == myEpoch else { return }
					// Append pre-utterance silence on first buffer (uses the
					// reinterpreted format as the template so the silence
					// matches the upcoming speech buffers exactly).
					if collection.collectedBuffers.isEmpty,
					   let silence = self.makeSilenceBuffer(seconds: preDelay, basedOn: reinterpreted) {
						collection.collectedBuffers.append(silence)
						collection.totalFrames += AVAudioFramePosition(silence.frameLength)
						if shouldEnqueueThisRender { self.player.enqueue(silence) }
					}
					collection.collectedBuffers.append(reinterpreted)
					collection.totalFrames += AVAudioFramePosition(reinterpreted.frameLength)
					if shouldEnqueueThisRender { self.player.enqueue(reinterpreted) }
				}
			}
		}
		let collectedBuffers = collection.collectedBuffers
		let totalFrames = collection.totalFrames

		// If our epoch is stale, this render was canceled by a seek/stop/play
		// before completion. Discard the result rather than recording it (the
		// new render plan, decided by ensureRenderingProgresses on the new
		// epoch, has its own intent for what this block index should hold).
		guard renderEpoch == myEpoch else { return }

		renderedBlocks[index] = RenderedBlock(
			blockIndex: index,
			startSampleTime: startSampleTime,
			totalFrames: totalFrames,
			buffers: collectedBuffers
		)

		// Update the player-queue watermark to reflect that buffer
		// callbacks enqueued this block's buffers (if we were going to).
		if shouldEnqueueThisRender {
			lastEnqueuedBlockIndex = max(lastEnqueuedBlockIndex, index)
		}
		// Try to extend the queue further forward — this render may have
		// filled in a gap, allowing the next already-rendered block to
		// be enqueued.
		topUpPlayerQueue()

		// If this was the current block and we haven't started yet, start.
		if index == currentBlockIndex, state == .preparing {
			player.play()
			state = .speaking(blockIndex: currentBlockIndex, totalBlocks: blocks.count)
		}
	}

	// MARK: - Buffer construction helpers

	/// Workaround for forum 684419: `AVSpeechSynthesizer.write`'s callback
	/// buffer is sometimes claimed as `pcmFormatInt32` big-endian but the
	/// underlying bytes are float32 native. We construct a new buffer with
	/// the correct format claim and copy the same raw bytes — the data is
	/// already the right type, just mislabeled.
	private func reinterpret(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
		guard let correctFormat = AVAudioFormat(
			commonFormat: .pcmFormatFloat32,
			sampleRate: buffer.format.sampleRate,
			channels: buffer.format.channelCount,
			interleaved: false
		), let copy = AVAudioPCMBuffer(pcmFormat: correctFormat, frameCapacity: buffer.frameLength) else {
			return buffer
		}
		copy.frameLength = buffer.frameLength
		let byteCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
		for channel in 0..<Int(buffer.format.channelCount) {
			guard let srcRaw = buffer.audioBufferList.pointee.mBuffers.mData,
				  let dstRaw = copy.audioBufferList.pointee.mBuffers.mData else { continue }
			UnsafeMutableRawPointer(dstRaw).advanced(by: channel * byteCount)
				.copyMemory(from: UnsafeRawPointer(srcRaw).advanced(by: channel * byteCount), byteCount: byteCount)
		}
		return copy
	}

	private func makeSilenceBuffer(seconds: TimeInterval, basedOn template: AVAudioPCMBuffer?) -> AVAudioPCMBuffer? {
		guard seconds > 0, let template else { return nil }
		let frameCount = AVAudioFrameCount(seconds * template.format.sampleRate)
		guard frameCount > 0,
			  let silence = AVAudioPCMBuffer(pcmFormat: template.format, frameCapacity: frameCount) else { return nil }
		silence.frameLength = frameCount
		// Buffer is zero-initialized — silent.
		return silence
	}

	private func makeUtterance(from block: SpeechBlock, voice: SpeechVoice) -> AVSpeechUtterance {
		let utterance = AVSpeechUtterance(string: block.text)
		utterance.voice = AVSpeechSynthesisVoice(identifier: voice.identifier) ?? AVSpeechSynthesisVoice(language: voice.language)
		utterance.rate = mapRate(rateMultiplier)
		// Pre/post utterance delays are inserted as silence buffers around the
		// speech buffers (see renderBlock). AVSpeechSynthesizer.write doesn't
		// honor AVSpeechUtterance.preUtteranceDelay / postUtteranceDelay —
		// those only fire during built-in playback via speak().
		return utterance
	}

	private func mapRate(_ multiplier: Float) -> Float {
		let avDefault = AVSpeechUtteranceDefaultSpeechRate
		let perStep: Float = 0.15
		let raw = avDefault + (multiplier - 1.0) * perStep
		return min(max(raw, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
	}

	private func estimateBlockFrames(at index: Int) -> AVAudioFramePosition {
		// Rough estimate used only for blocks not yet rendered. ~15 chars per
		// second corresponds to ~180 wpm × 5 chars/word ÷ 60s, matching what
		// AVSpeechSynthesizer at default rate empirically produces. Once a
		// block renders, its actual `totalFrames` replaces this estimate in
		// `durationSeconds` so the displayed duration converges to truth.
		guard index < blocks.count else { return 0 }
		let chars = blocks[index].text.count
		let seconds = Double(chars) / 15.0
		let sampleRate = player.sampleRate > 0 ? player.sampleRate : 22050
		return AVAudioFramePosition(seconds * sampleRate)
	}

	// MARK: - Observer dispatch

	private func notifyObservers() {
		for case let observer as SpeechSynthObserver in observers.allObjects {
			observer.speechSynth(self, didChangeState: state)
		}
	}

	// MARK: - Audio session (iOS only)

	#if os(iOS)
	private func activateAudioSessionIfNeeded() {
		do {
			let avAudioSession = AVAudioSession.sharedInstance()
			try avAudioSession.setCategory(.playback, mode: .spokenAudio, options: [])
			try avAudioSession.setActive(true, options: [])
		} catch {
			log.warning("Failed to activate AVAudioSession: \(error.localizedDescription, privacy: .public)")
		}
	}

	private func deactivateAudioSession() {
		do {
			try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
		} catch {
			// Ignore — deactivation failure is non-fatal.
		}
	}
	#else
	private func activateAudioSessionIfNeeded() {}
	private func deactivateAudioSession() {}
	#endif
}

// MARK: - RenderedBlock

private struct RenderedBlock {
	let blockIndex: Int
	let startSampleTime: AVAudioFramePosition
	let totalFrames: AVAudioFramePosition
	let buffers: [AVAudioPCMBuffer]
}

// MARK: - AudioBufferPlayerObserver

extension AppleSpeechSynth: AudioBufferPlayerObserver {

	public func audioBufferPlayer(_ player: AudioBufferPlayer, didChangeState state: AudioBufferPlayerState) {
		switch state {
		case .playing:
			self.state = .speaking(blockIndex: currentBlockIndex, totalBlocks: blocks.count)
		case .paused, .interrupted:
			self.state = .paused(blockIndex: currentBlockIndex, totalBlocks: blocks.count)
		case .finished:
			// Only honor `.finished` from the player when we've actually
			// reached the end of the loaded content. The player transitions
			// to `.finished` whenever its queue empties, which can happen
			// transiently during block-boundary underflow (next block still
			// rendering) — in that case the synth is NOT finished, just
			// waiting for the next block's buffers. AudioBufferPlayer.enqueue
			// recovers state to .playing when those buffers arrive.
			let isLastBlockFullyRendered = renderingTask == nil
				&& !blocks.isEmpty
				&& currentBlockIndex >= blocks.count - 1
				&& renderedBlocks[blocks.count - 1] != nil
			if isLastBlockFullyRendered {
				self.state = .finished
				deactivateAudioSession()
			}
		case .idle:
			// Only transition to .idle if we're not in the middle of a render
			// and there's no content loaded. Otherwise leave the synth's state
			// alone — the player's .idle is during seek/stop transients.
			if renderingTask == nil && blocks.isEmpty {
				self.state = .idle
			}
		case .preparing:
			self.state = .preparing
		}
	}

	public func audioBufferPlayer(_ player: AudioBufferPlayer, didAdvanceTo sampleTime: AVAudioFramePosition) {
		// Detect block advance: if the sample-time has crossed into a later
		// block's boundary, update currentBlockIndex and trigger
		// eviction + further prefetch.
		guard let newBlock = blockIndex(forSampleTime: sampleTime), newBlock != currentBlockIndex else {
			return
		}
		currentBlockIndex = newBlock
		evictOutOfWindow()
		// Extend the player queue: as `currentBlockIndex` slides forward,
		// further already-rendered blocks become eligible for enqueue.
		// Without this, after a skip-back's `resetQueue` covers only
		// [target, target+prefetchAhead], the player runs out when the
		// window slides past — every already-rendered forward block needs
		// re-enqueueing.
		topUpPlayerQueue()
		ensureRenderingProgresses()
		// Update blockIndex in the synth state without changing
		// playing/paused-ness: if the user paused the player between
		// scheduling a buffer and its `.dataPlayedBack` callback firing, the
		// callback can race with the pause and we'd otherwise overwrite
		// `.paused` with `.speaking` here.
		switch state {
		case .paused:
			state = .paused(blockIndex: newBlock, totalBlocks: blocks.count)
		case .speaking:
			state = .speaking(blockIndex: newBlock, totalBlocks: blocks.count)
		default:
			// .idle / .preparing / .finished — block advance is meaningful
			// only when we're actually playing or paused mid-playback. Skip.
			break
		}
	}
}
