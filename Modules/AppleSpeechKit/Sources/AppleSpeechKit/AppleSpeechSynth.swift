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
}

// MARK: - AppleSpeechEngineDelegate

extension AppleSpeechSynth: AppleSpeechEngineDelegate {

	func engineDidStart(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		state = .speaking(blockIndex: currentIndex, totalBlocks: avSpeechUtterances.count)
	}

	func engineDidFinish(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		let nextIndex = currentIndex + 1
		if nextIndex < avSpeechUtterances.count {
			pendingAction = .advance
			currentIndex = nextIndex
			state = .speaking(blockIndex: currentIndex, totalBlocks: avSpeechUtterances.count)
			engine.speak(avSpeechUtterances[nextIndex])
		} else {
			pendingAction = .none
			state = .finished
		}
	}

	func engineDidPause(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		state = .paused(blockIndex: currentIndex, totalBlocks: avSpeechUtterances.count)
	}

	func engineDidContinue(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		state = .speaking(blockIndex: currentIndex, totalBlocks: avSpeechUtterances.count)
	}

	func engineDidCancel(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance) {
		switch pendingAction {
		case .replaceWith(let newAVSpeechUtterances):
			pendingAction = .none
			avSpeechUtterances = newAVSpeechUtterances
			currentIndex = 0
			guard let first = newAVSpeechUtterances.first else {
				state = .idle
				return
			}
			state = .preparing
			engine.speak(first)
		case .skipTo(let idx):
			pendingAction = .none
			currentIndex = idx
			state = .preparing
			engine.speak(avSpeechUtterances[idx])
		case .fullStop:
			pendingAction = .none
			avSpeechUtterances = []
			currentIndex = 0
			state = .idle
		case .none, .advance:
			pendingAction = .none
			avSpeechUtterances = []
			currentIndex = 0
			state = .idle
		}
	}
}
