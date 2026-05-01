import Foundation
import AVFoundation

/// Internal protocol seam over `AVSpeechSynthesizer`. Production uses
/// `AVSpeechSynthesizerEngine`; tests use a mock that fires arbitrary
/// delegate sequences.
@MainActor
protocol AppleSpeechEngine: AnyObject {
	var isSpeaking: Bool { get }
	var isPaused: Bool { get }
	var delegate: AppleSpeechEngineDelegate? { get set }

	func speak(_ avSpeechUtterance: AVSpeechUtterance)
	func pauseSpeaking(at boundary: AVSpeechBoundary)
	func continueSpeaking()
	func stopSpeaking(at boundary: AVSpeechBoundary)
}

@MainActor
protocol AppleSpeechEngineDelegate: AnyObject {
	func engineDidStart(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance)
	func engineDidFinish(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance)
	func engineDidPause(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance)
	func engineDidContinue(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance)
	func engineDidCancel(_ engine: AppleSpeechEngine, avSpeechUtterance: AVSpeechUtterance)
}
