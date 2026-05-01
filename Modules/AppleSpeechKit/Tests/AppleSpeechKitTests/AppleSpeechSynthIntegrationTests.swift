import Testing
import Foundation
import AVFoundation
import ArticleSpeech
@testable import AppleSpeechKit

@MainActor
struct AppleSpeechSynthIntegrationTests {

	/// End-to-end smoke test against the real `AVSpeechSynthesizerEngine`. Plays
	/// a single short block and verifies the state machine reaches `.finished`
	/// within a generous timeout. Slower than the mock-engine state-machine
	/// tests because it actually emits audio; kept to one block to bound the
	/// runtime.
	@Test func playSingleBlockReachesFinishedWithinTimeout() async throws {
		let synth = AppleSpeechSynth()  // uses real AVSpeechSynthesizerEngine
		let voice = AppleSpeechVoiceCatalog.systemDefault
		let blocks = [SpeechBlock(text: "Hello.", kind: .paragraph)]

		final class StateRecorder: SpeechSynthObserver {
			var lastState: SpeechSynthState = .idle
			func speechSynth(_ synth: SpeechSynth, didChangeState state: SpeechSynthState) {
				lastState = state
			}
		}
		let recorder = StateRecorder()
		synth.addObserver(recorder)

		synth.play(blocks: blocks, voice: voice, rate: 1.0)

		// Poll for up to 10s for state == .finished. AVSpeech needs real time
		// to actually speak the utterance; "Hello." typically takes ~1s.
		let deadline = Date().addingTimeInterval(10)
		while Date() < deadline {
			if recorder.lastState == .finished { break }
			try await Task.sleep(nanoseconds: 50_000_000)
		}
		#expect(recorder.lastState == .finished)
	}
}
