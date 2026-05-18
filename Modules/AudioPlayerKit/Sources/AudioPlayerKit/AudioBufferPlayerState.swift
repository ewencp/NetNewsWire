import Foundation

public enum AudioBufferPlayerState: Equatable, Sendable {
	/// No buffers scheduled and engine not running.
	case idle
	/// Engine starting up or no buffers yet to play.
	case preparing
	/// Actively rendering audio to the output.
	case playing
	/// User-initiated pause.
	case paused
	/// System-paused due to AVAudioSession interruption.
	case interrupted
	/// All scheduled buffers consumed and no more arriving.
	case finished
}
