import Foundation
import AVFoundation

/// Wraps a value so it can cross isolation boundaries. Used here because
/// `AVSpeechUtterance` is not (yet) `Sendable`, but we know it's safe to pass
/// through a delegate hop on the main thread.
private struct UncheckedSendable<T>: @unchecked Sendable {
	let value: T
}

@MainActor
final class AVSpeechSynthesizerEngine: NSObject, AppleSpeechEngine, AVSpeechSynthesizerDelegate {

	private let avSpeechSynthesizer: AVSpeechSynthesizer
	weak var delegate: AppleSpeechEngineDelegate?

	override init() {
		self.avSpeechSynthesizer = AVSpeechSynthesizer()
		super.init()
		self.avSpeechSynthesizer.delegate = self
	}

	var isSpeaking: Bool { avSpeechSynthesizer.isSpeaking }
	var isPaused: Bool { avSpeechSynthesizer.isPaused }

	func speak(_ avSpeechUtterance: AVSpeechUtterance) {
		avSpeechSynthesizer.speak(avSpeechUtterance)
	}

	func pauseSpeaking(at boundary: AVSpeechBoundary) {
		avSpeechSynthesizer.pauseSpeaking(at: boundary)
	}

	func continueSpeaking() {
		avSpeechSynthesizer.continueSpeaking()
	}

	func stopSpeaking(at boundary: AVSpeechBoundary) {
		avSpeechSynthesizer.stopSpeaking(at: boundary)
	}

	// MARK: - AVSpeechSynthesizerDelegate
	//
	// AVSpeechSynthesizer dispatches its delegate callbacks on the main thread by
	// default. We hop through `MainActor.assumeIsolated` and wrap the utterance
	// in `UncheckedSendable` because `AVSpeechUtterance` isn't yet `Sendable`.

	nonisolated func speechSynthesizer(_ avSpeechSynthesizer: AVSpeechSynthesizer, didStart avSpeechUtterance: AVSpeechUtterance) {
		let captured = UncheckedSendable(value: avSpeechUtterance)
		MainActor.assumeIsolated {
			delegate?.engineDidStart(self, avSpeechUtterance: captured.value)
		}
	}

	nonisolated func speechSynthesizer(_ avSpeechSynthesizer: AVSpeechSynthesizer, didFinish avSpeechUtterance: AVSpeechUtterance) {
		let captured = UncheckedSendable(value: avSpeechUtterance)
		MainActor.assumeIsolated {
			delegate?.engineDidFinish(self, avSpeechUtterance: captured.value)
		}
	}

	nonisolated func speechSynthesizer(_ avSpeechSynthesizer: AVSpeechSynthesizer, didPause avSpeechUtterance: AVSpeechUtterance) {
		let captured = UncheckedSendable(value: avSpeechUtterance)
		MainActor.assumeIsolated {
			delegate?.engineDidPause(self, avSpeechUtterance: captured.value)
		}
	}

	nonisolated func speechSynthesizer(_ avSpeechSynthesizer: AVSpeechSynthesizer, didContinue avSpeechUtterance: AVSpeechUtterance) {
		let captured = UncheckedSendable(value: avSpeechUtterance)
		MainActor.assumeIsolated {
			delegate?.engineDidContinue(self, avSpeechUtterance: captured.value)
		}
	}

	nonisolated func speechSynthesizer(_ avSpeechSynthesizer: AVSpeechSynthesizer, didCancel avSpeechUtterance: AVSpeechUtterance) {
		let captured = UncheckedSendable(value: avSpeechUtterance)
		MainActor.assumeIsolated {
			delegate?.engineDidCancel(self, avSpeechUtterance: captured.value)
		}
	}
}
