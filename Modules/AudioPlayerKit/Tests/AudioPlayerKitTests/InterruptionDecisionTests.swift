#if os(iOS)
import Testing
import AVFoundation
@testable import AudioPlayerKit

struct InterruptionDecisionTests {

	// MARK: - .began transitions

	@Test
	func beganWhilePlaying_returnsBeginInterruptionWithRememberToResume() {
		let action = InterruptionDecision.decide(
			type: .began,
			options: [],
			currentState: .playing,
			wasPlayingBeforeInterruption: false
		)
		#expect(action == .beginInterruption(rememberToResume: true))
	}

	@Test
	func beganWhilePreparing_returnsBeginInterruptionWithRememberToResume() {
		let action = InterruptionDecision.decide(
			type: .began,
			options: [],
			currentState: .preparing,
			wasPlayingBeforeInterruption: false
		)
		#expect(action == .beginInterruption(rememberToResume: true))
	}

	@Test
	func beganWhilePaused_returnsIgnore() {
		let action = InterruptionDecision.decide(
			type: .began,
			options: [],
			currentState: .paused,
			wasPlayingBeforeInterruption: false
		)
		#expect(action == .ignore)
	}

	@Test
	func beganWhileIdle_returnsBeginInterruptionWithoutResume() {
		let action = InterruptionDecision.decide(
			type: .began,
			options: [],
			currentState: .idle,
			wasPlayingBeforeInterruption: false
		)
		#expect(action == .beginInterruption(rememberToResume: false))
	}

	@Test
	func beganWhileFinished_returnsBeginInterruptionWithoutResume() {
		let action = InterruptionDecision.decide(
			type: .began,
			options: [],
			currentState: .finished,
			wasPlayingBeforeInterruption: false
		)
		#expect(action == .beginInterruption(rememberToResume: false))
	}

	@Test
	func beganWhileAlreadyInterrupted_returnsBeginInterruptionWithoutResume() {
		// Defensive: if a second .began arrives without an intervening .ended,
		// don't fabricate a resume intent that wasn't there.
		let action = InterruptionDecision.decide(
			type: .began,
			options: [],
			currentState: .interrupted,
			wasPlayingBeforeInterruption: false
		)
		#expect(action == .beginInterruption(rememberToResume: false))
	}

	// MARK: - .ended transitions

	@Test
	func endedWithShouldResumeAndWasPlaying_returnsAttemptResume() {
		let action = InterruptionDecision.decide(
			type: .ended,
			options: [.shouldResume],
			currentState: .interrupted,
			wasPlayingBeforeInterruption: true
		)
		#expect(action == .attemptResume)
	}

	@Test
	func endedWithoutShouldResume_returnsAcknowledgeEnd() {
		let action = InterruptionDecision.decide(
			type: .ended,
			options: [],
			currentState: .interrupted,
			wasPlayingBeforeInterruption: true
		)
		#expect(action == .acknowledgeEnd)
	}

	@Test
	func endedWithShouldResumeButNotPlaying_returnsAcknowledgeEnd() {
		// The user-paused case: .began preserved .paused; .ended with
		// .shouldResume should NOT auto-resume because wasPlaying is false.
		let action = InterruptionDecision.decide(
			type: .ended,
			options: [.shouldResume],
			currentState: .paused,
			wasPlayingBeforeInterruption: false
		)
		#expect(action == .acknowledgeEnd)
	}

	@Test
	func endedWithoutShouldResumeAndNotPlaying_returnsAcknowledgeEnd() {
		let action = InterruptionDecision.decide(
			type: .ended,
			options: [],
			currentState: .paused,
			wasPlayingBeforeInterruption: false
		)
		#expect(action == .acknowledgeEnd)
	}
}
#endif
