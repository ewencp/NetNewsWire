import Foundation

public enum SpeechSynthState: Sendable, Equatable {
	case idle
	case preparing
	case speaking(blockIndex: Int, totalBlocks: Int)
	case paused(blockIndex: Int, totalBlocks: Int)
	case finished
	case failed(SpeechSynthError)

	public var isActive: Bool {
		switch self {
		case .preparing, .speaking, .paused, .failed:
			return true
		case .idle, .finished:
			return false
		}
	}

	public var blockProgress: (index: Int, total: Int)? {
		switch self {
		case .speaking(let i, let n), .paused(let i, let n):
			return (i, n)
		case .idle, .preparing, .finished, .failed:
			return nil
		}
	}
}

public enum SpeechSynthError: Error, Sendable, Equatable {
	case voiceUnavailable(identifier: String)
	case backendUnavailable
	case interrupted
	case other(String)
}
