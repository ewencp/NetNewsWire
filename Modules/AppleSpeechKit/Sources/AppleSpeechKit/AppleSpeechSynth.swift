import Foundation
import AVFoundation
import ArticleSpeech

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

	// MARK: - Private state

	private let engine: AppleSpeechEngine
	private var avSpeechUtterances: [AVSpeechUtterance] = []
	private var currentIndex: Int = 0
	private var pendingAction: PendingAction = .none
	private var rateMultiplier: Float = 1.0
	private let observers = NSHashTable<AnyObject>.weakObjects()

	// MARK: - Initialization

	public convenience init() {
		self.init(engine: AVSpeechSynthesizerEngine())
	}

	init(engine: AppleSpeechEngine) {
		self.engine = engine
		self.engine.delegate = self
	}

	// MARK: - SpeechSynth conformance

	public func play(blocks: [SpeechBlock], voice: SpeechVoice, rate: Float) {
		self.rateMultiplier = rate
		let avSpeechSynthesisVoice = resolveAVSpeechSynthesisVoice(voice)
		let newAVSpeechUtterances = blocks.map {
			makeAVSpeechUtterance(from: $0, avSpeechSynthesisVoice: avSpeechSynthesisVoice)
		}

		let isBusy = engine.isSpeaking || engine.isPaused

		if !isBusy {
			avSpeechUtterances = newAVSpeechUtterances
			currentIndex = 0
			pendingAction = .none
			guard let first = newAVSpeechUtterances.first else {
				state = .idle
				return
			}
			state = .preparing
			activateAudioSessionIfNeeded()
			engine.speak(first)
			return
		}

		pendingAction = .replaceWith(newAVSpeechUtterances)
		engine.stopSpeaking(at: .immediate)
	}

	public func pause()  { engine.pauseSpeaking(at: .word) }
	public func resume() { engine.continueSpeaking() }

	public func stop() {
		guard !avSpeechUtterances.isEmpty else { return }
		pendingAction = .fullStop
		engine.stopSpeaking(at: .immediate)
	}

	public func skipForward() {
		guard !avSpeechUtterances.isEmpty else { return }
		// Compound rapid skips: if a skip is already pending, advance from its target.
		let baseIndex: Int
		if case .skipTo(let pending) = pendingAction {
			baseIndex = pending
		} else {
			baseIndex = currentIndex
		}
		let next = min(baseIndex + 1, avSpeechUtterances.count - 1)
		pendingAction = .skipTo(next)
		engine.stopSpeaking(at: .immediate)
	}

	public func skipBackward() {
		guard !avSpeechUtterances.isEmpty else { return }
		let baseIndex: Int
		if case .skipTo(let pending) = pendingAction {
			baseIndex = pending
		} else {
			baseIndex = currentIndex
		}
		let prev = max(baseIndex - 1, 0)
		pendingAction = .skipTo(prev)
		engine.stopSpeaking(at: .immediate)
	}

	public func addObserver(_ observer: SpeechSynthObserver) { observers.add(observer) }
	public func removeObserver(_ observer: SpeechSynthObserver) { observers.remove(observer) }

	// MARK: - Private types

	private enum PendingAction {
		case none
		case advance
		case skipTo(Int)
		case fullStop
		case replaceWith([AVSpeechUtterance])
	}

	// MARK: - Utterance construction

	private func makeAVSpeechUtterance(
		from block: SpeechBlock,
		avSpeechSynthesisVoice: AVSpeechSynthesisVoice?
	) -> AVSpeechUtterance {
		let avSpeechUtterance = AVSpeechUtterance(string: block.text)
		avSpeechUtterance.voice = avSpeechSynthesisVoice
		avSpeechUtterance.rate = mapRate(rateMultiplier)
		switch block.kind {
		case .heading:
			avSpeechUtterance.preUtteranceDelay = 0.4
			avSpeechUtterance.postUtteranceDelay = 0.5
		case .paragraph:
			avSpeechUtterance.postUtteranceDelay = 0.3
		case .blockQuote:
			avSpeechUtterance.preUtteranceDelay = 0.3
			avSpeechUtterance.postUtteranceDelay = 0.4
		case .imageDescription, .figureDescription:
			avSpeechUtterance.preUtteranceDelay = 0.2
			avSpeechUtterance.postUtteranceDelay = 0.3
		case .codeNotice, .tableNotice:
			avSpeechUtterance.preUtteranceDelay = 0.2
			avSpeechUtterance.postUtteranceDelay = 0.3
		case .listItem:
			avSpeechUtterance.postUtteranceDelay = 0.15
		}
		return avSpeechUtterance
	}

	private func resolveAVSpeechSynthesisVoice(_ voice: SpeechVoice) -> AVSpeechSynthesisVoice? {
		AVSpeechSynthesisVoice(identifier: voice.identifier)
			?? AVSpeechSynthesisVoice(language: voice.language)
	}

	private func mapRate(_ multiplier: Float) -> Float {
		let avSpeechDefault = AVSpeechUtteranceDefaultSpeechRate
		let perStep: Float = 0.15
		let raw = avSpeechDefault + (multiplier - 1.0) * perStep
		return min(max(raw, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
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
			// Non-fatal — playback still works without optimal session config.
		}
	}

	private func deactivateAudioSession() {
		do {
			try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
		} catch {
			// Ignore.
		}
	}
	#else
	private func activateAudioSessionIfNeeded() {}
	private func deactivateAudioSession() {}
	#endif
}

// MARK: - AppleSpeechEngineDelegate

extension AppleSpeechSynth: AppleSpeechEngineDelegate {

	func engineDidStart(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		state = .speaking(blockIndex: currentIndex, totalBlocks: avSpeechUtterances.count)
	}

	func engineDidFinish(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		// AVSpeech's stopSpeaking is asynchronous; if the current utterance finishes
		// naturally before our stop's didCancel fires, we land here with a non-trivial
		// pendingAction (replaceWith / skipTo / fullStop) queued by play()/skipForward()/
		// skipBackward()/stop(). Honor the pending action instead of auto-advancing —
		// otherwise the user sees "stop" or "skip" silently behave as "fast forward."
		if applyPendingActionIfNeeded(via: engine) {
			return
		}
		// Natural advance path.
		let nextIndex = currentIndex + 1
		if nextIndex < avSpeechUtterances.count {
			pendingAction = .advance
			currentIndex = nextIndex
			state = .speaking(blockIndex: currentIndex, totalBlocks: avSpeechUtterances.count)
			engine.speak(avSpeechUtterances[nextIndex])
		} else {
			pendingAction = .none
			state = .finished
			deactivateAudioSession()
		}
	}

	/// Consumes any non-trivial `pendingAction` (replaceWith / skipTo / fullStop) and
	/// returns true if the action was applied. Called from both `engineDidFinish`
	/// (when the utterance naturally finishes mid-stop) and `engineDidCancel` (the
	/// normal stopSpeaking path) so either ordering produces the same user-visible
	/// outcome.
	private func applyPendingActionIfNeeded(via engine: AppleSpeechEngine) -> Bool {
		switch pendingAction {
		case .replaceWith(let newAVSpeechUtterances):
			pendingAction = .none
			avSpeechUtterances = newAVSpeechUtterances
			currentIndex = 0
			guard let first = newAVSpeechUtterances.first else {
				state = .idle
				deactivateAudioSession()
				return true
			}
			state = .preparing
			engine.speak(first)
			return true
		case .skipTo(let idx):
			pendingAction = .none
			currentIndex = idx
			state = .preparing
			engine.speak(avSpeechUtterances[idx])
			return true
		case .fullStop:
			pendingAction = .none
			avSpeechUtterances = []
			currentIndex = 0
			state = .idle
			deactivateAudioSession()
			return true
		case .none, .advance:
			return false
		}
	}

	func engineDidPause(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		state = .paused(blockIndex: currentIndex, totalBlocks: avSpeechUtterances.count)
	}

	func engineDidContinue(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		state = .speaking(blockIndex: currentIndex, totalBlocks: avSpeechUtterances.count)
	}

	func engineDidCancel(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		if applyPendingActionIfNeeded(via: engine) {
			return
		}
		// Spurious cancel — defensive reset.
		pendingAction = .none
		avSpeechUtterances = []
		currentIndex = 0
		state = .idle
		deactivateAudioSession()
	}
}
