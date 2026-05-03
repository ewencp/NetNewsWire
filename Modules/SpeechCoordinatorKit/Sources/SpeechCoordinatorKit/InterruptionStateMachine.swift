import Foundation
import ArticleSpeech

/// Neutral representation of an audio-session interruption event, decoupled
/// from `AVAudioSession.InterruptionType` so the state machine stays testable
/// cross-platform. The iOS presenter translates the system notification into
/// this enum before invoking `transition`.
public enum InterruptionEvent: Equatable, Sendable {
	case began
	case ended(shouldResume: Bool)
}

/// The action the caller should take in response to an interruption transition.
public enum InterruptionAction: Equatable, Sendable {
	case none
	case togglePlayPause
}

/// Pure-function state machine for audio-session interruption handling.
///
/// The presenter holds a single bit of state (`pendingResumeFromInterruption`)
/// and feeds events through this transition function to decide whether to
/// pause/resume playback and how to update the bit.
public enum InterruptionStateMachine {

	public struct Outcome: Equatable, Sendable {
		public let action: InterruptionAction
		public let newPendingResume: Bool

		public init(action: InterruptionAction, newPendingResume: Bool) {
			self.action = action
			self.newPendingResume = newPendingResume
		}
	}

	public static func transition(
		currentState: SpeechSynthState,
		event: InterruptionEvent,
		pendingResume: Bool
	) -> Outcome {
		switch event {
		case .began:
			if case .speaking = currentState {
				return Outcome(action: .togglePlayPause, newPendingResume: true)
			}
			return Outcome(action: .none, newPendingResume: pendingResume)

		case .ended(let shouldResume):
			if shouldResume && pendingResume {
				return Outcome(action: .togglePlayPause, newPendingResume: false)
			}
			return Outcome(action: .none, newPendingResume: false)
		}
	}
}
