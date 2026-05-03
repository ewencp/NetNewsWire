import Testing
@testable import SpeechCoordinatorKit

struct InterruptionStateMachineTests {

	@Test func beganWhileSpeakingPausesAndSetsFlag() {
		let outcome = InterruptionStateMachine.transition(
			currentState: .speaking(blockIndex: 0, totalBlocks: 5),
			event: .began,
			pendingResume: false
		)
		#expect(outcome.action == .togglePlayPause)
		#expect(outcome.newPendingResume == true)
	}

	@Test func beganWhilePausedDoesNothing() {
		let outcome = InterruptionStateMachine.transition(
			currentState: .paused(blockIndex: 0, totalBlocks: 5),
			event: .began,
			pendingResume: false
		)
		#expect(outcome.action == .none)
		#expect(outcome.newPendingResume == false)
	}

	@Test func beganWhileIdleDoesNothing() {
		let outcome = InterruptionStateMachine.transition(
			currentState: .idle,
			event: .began,
			pendingResume: false
		)
		#expect(outcome.action == .none)
		#expect(outcome.newPendingResume == false)
	}

	@Test func endedShouldResumeWithFlagResumes() {
		let outcome = InterruptionStateMachine.transition(
			currentState: .paused(blockIndex: 0, totalBlocks: 5),
			event: .ended(shouldResume: true),
			pendingResume: true
		)
		#expect(outcome.action == .togglePlayPause)
		#expect(outcome.newPendingResume == false)
	}

	@Test func endedShouldResumeWithoutFlagDoesNotResume() {
		let outcome = InterruptionStateMachine.transition(
			currentState: .paused(blockIndex: 0, totalBlocks: 5),
			event: .ended(shouldResume: true),
			pendingResume: false
		)
		#expect(outcome.action == .none)
		#expect(outcome.newPendingResume == false)
	}

	@Test func endedWithoutShouldResumeClearsFlag() {
		let outcome = InterruptionStateMachine.transition(
			currentState: .paused(blockIndex: 0, totalBlocks: 5),
			event: .ended(shouldResume: false),
			pendingResume: true
		)
		#expect(outcome.action == .none)
		#expect(outcome.newPendingResume == false)
	}
}
