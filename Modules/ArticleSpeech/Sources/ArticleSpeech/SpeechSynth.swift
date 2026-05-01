import Foundation

@MainActor
public protocol SpeechSynth: AnyObject {

	var state: SpeechSynthState { get }
	var isAvailable: Bool { get async }

	func availableVoices() async -> [SpeechVoice]

	func play(blocks: [SpeechBlock], voice: SpeechVoice, rate: Float, startingAt: Int)
	func pause()
	func resume()
	func stop()
	func skipForward()
	func skipBackward()

	func addObserver(_ observer: SpeechSynthObserver)
	func removeObserver(_ observer: SpeechSynthObserver)
}

@MainActor
public protocol SpeechSynthObserver: AnyObject {
	func speechSynth(_ synth: SpeechSynth, didChangeState state: SpeechSynthState)
}

public extension SpeechSynth {
	/// Convenience overload for the common case of starting from the first block.
	func play(blocks: [SpeechBlock], voice: SpeechVoice, rate: Float) {
		play(blocks: blocks, voice: voice, rate: rate, startingAt: 0)
	}
}
