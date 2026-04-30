import Foundation

public protocol SpeechSynth: AnyObject {

	var state: SpeechSynthState { get }
	var isAvailable: Bool { get async }

	func availableVoices() async -> [SpeechVoice]

	func play(blocks: [SpeechBlock], voice: SpeechVoice, rate: Float)
	func pause()
	func resume()
	func stop()
	func skipForward()
	func skipBackward()

	func addObserver(_ observer: SpeechSynthObserver)
	func removeObserver(_ observer: SpeechSynthObserver)
}

public protocol SpeechSynthObserver: AnyObject {
	func speechSynth(_ synth: SpeechSynth, didChangeState state: SpeechSynthState)
}
