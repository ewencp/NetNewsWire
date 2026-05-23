import Foundation

@MainActor
public protocol SpeechSynth: AnyObject {

	var state: SpeechSynthState { get }
	var isAvailable: Bool { get async }

	/// Total estimated duration of the currently-loaded content, in seconds.
	/// Returns 0 if nothing is loaded.
	var durationSeconds: Double { get }

	/// Time elapsed since the start of the current content, in seconds.
	/// Returns 0 if nothing is playing.
	var elapsedSeconds: Double { get }

	func availableVoices() async -> [SpeechVoice]

	func play(blocks: [SpeechBlock], voice: SpeechVoice, rate: Float, startingAt: Int)
	func pause()
	func resume()
	func stop()
	func skipForward()
	func skipBackward()

	/// Seek to the given offset (in seconds) from the start of the current content.
	func seek(toSeconds seconds: Double)

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
