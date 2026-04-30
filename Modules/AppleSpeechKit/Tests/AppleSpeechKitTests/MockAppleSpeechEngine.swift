import Foundation
import AVFoundation
@testable import AppleSpeechKit

@MainActor
final class MockAppleSpeechEngine: AppleSpeechEngine {

	weak var delegate: AppleSpeechEngineDelegate?
	var isSpeaking: Bool = false
	var isPaused: Bool = false

	private(set) var spoken: [AVSpeechUtterance] = []
	private(set) var pauseCount = 0
	private(set) var continueCount = 0
	private(set) var stopCount = 0

	func speak(_ avSpeechUtterance: AVSpeechUtterance) {
		spoken.append(avSpeechUtterance)
		isSpeaking = true
		isPaused = false
	}

	func pauseSpeaking(at boundary: AVSpeechBoundary) {
		pauseCount += 1
		isPaused = true
	}

	func continueSpeaking() {
		continueCount += 1
		isPaused = false
	}

	func stopSpeaking(at boundary: AVSpeechBoundary) {
		stopCount += 1
		isSpeaking = false
		isPaused = false
	}

	// MARK: - Test helpers — fire delegate events

	func fireDidStart(_ avSpeechUtterance: AVSpeechUtterance) {
		delegate?.engineDidStart(self, avSpeechUtterance: avSpeechUtterance)
	}

	func fireDidFinish(_ avSpeechUtterance: AVSpeechUtterance) {
		isSpeaking = false
		delegate?.engineDidFinish(self, avSpeechUtterance: avSpeechUtterance)
	}

	func fireDidPause(_ avSpeechUtterance: AVSpeechUtterance) {
		delegate?.engineDidPause(self, avSpeechUtterance: avSpeechUtterance)
	}

	func fireDidContinue(_ avSpeechUtterance: AVSpeechUtterance) {
		delegate?.engineDidContinue(self, avSpeechUtterance: avSpeechUtterance)
	}

	func fireDidCancel(_ avSpeechUtterance: AVSpeechUtterance) {
		isSpeaking = false
		isPaused = false
		delegate?.engineDidCancel(self, avSpeechUtterance: avSpeechUtterance)
	}
}
