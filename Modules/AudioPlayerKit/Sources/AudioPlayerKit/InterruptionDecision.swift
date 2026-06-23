#if os(iOS)
import AVFoundation

/// Pure decision logic for `AVAudioSession.interruptionNotification` handling.
///
/// Separates "what to do given an interruption event" from "how to wire it up
/// (observers, MainActor hops, engine state)." The decision is a pure function
/// of inputs — making it exhaustively unit-testable without the timing
/// dependencies that make notification-based integration tests flaky.
///
/// The integration boundary (`AudioBufferPlayer.handleInterruption`) decodes
/// the notification, calls `decide`, then applies the resulting `Action`. Real
/// device verification of the wiring is documented in the iOS TTS manual test
/// runbook.
public enum InterruptionAction: Equatable {

	/// Preserve the current state. Used when the player was paused before the
	/// interruption — a user-initiated state that should survive the
	/// interruption rather than being reclassified as `.interrupted`.
	case ignore

	/// Transition to `.interrupted`. `rememberToResume` indicates whether
	/// playback was actually active before the interruption (true) or the
	/// player was idle/finished/already-interrupted (false). The flag is used
	/// later by `.ended` to decide whether auto-resume is appropriate.
	case beginInterruption(rememberToResume: Bool)

	/// Attempt to resume playback: reactivate the audio session, restart the
	/// engine if needed, and resume the player node. The integration layer
	/// decides actual success and handles errors.
	case attemptResume

	/// Acknowledge the interruption ending without resuming. Reset the
	/// remember-to-resume flag. Used when `.shouldResume` is absent, or when
	/// the player wasn't actively playing before the interruption.
	case acknowledgeEnd
}

public enum InterruptionDecision {

	public static func decide(
		type: AVAudioSession.InterruptionType,
		options: AVAudioSession.InterruptionOptions,
		currentState: AudioBufferPlayerState,
		wasPlayingBeforeInterruption: Bool
	) -> InterruptionAction {
		switch type {
		case .began:
			// Per Apple FW Engineer (forum 663604): "Typically, do nothing
			// when interruption begins." We just record what we observed.
			// .paused is the one state we preserve — overwriting it with
			// .interrupted would strand the player after .ended.
			if currentState == .paused {
				return .ignore
			}
			let wasActive = (currentState == .playing || currentState == .preparing)
			return .beginInterruption(rememberToResume: wasActive)

		case .ended:
			let shouldResume = options.contains(.shouldResume) && wasPlayingBeforeInterruption
			return shouldResume ? .attemptResume : .acknowledgeEnd

		@unknown default:
			return .ignore
		}
	}
}
#endif
