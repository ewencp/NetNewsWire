import Testing
import Foundation
import AVFoundation
import ArticleSpeech
@testable import AppleSpeechKit

@MainActor
struct AppleSpeechSynthTests {

	private func makeBlocks(_ texts: [String]) -> [SpeechBlock] {
		texts.map { SpeechBlock(text: $0, kind: .paragraph) }
	}

	private func makeVoice() -> SpeechVoice {
		SpeechVoice(
			identifier: AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? "x",
			displayName: "Test",
			language: "en-US",
			qualityTier: .standard,
			gender: .unspecified,
			isInstalled: true
		)
	}

	// MARK: - Basic playback

	@Test func playFromIdleSpeaksFirstUtteranceAndEntersPreparing() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		synth.play(blocks: makeBlocks(["A.", "B.", "C."]), voice: makeVoice(), rate: 1.0)
		#expect(mockEngine.spoken.count == 1)
		#expect(synth.state == .preparing)
	}

	@Test func didStartTransitionsToSpeakingAtIndexZero() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		let blocks = makeBlocks(["A.", "B.", "C."])
		synth.play(blocks: blocks, voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		#expect(synth.state == .speaking(blockIndex: 0, totalBlocks: 3))
	}

	@Test func didFinishAdvancesToNextBlock() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		let blocks = makeBlocks(["A.", "B.", "C."])
		synth.play(blocks: blocks, voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		mockEngine.fireDidFinish(mockEngine.spoken[0])
		#expect(mockEngine.spoken.count == 2)
		#expect(synth.state == .speaking(blockIndex: 1, totalBlocks: 3))
	}

	@Test func didFinishLastBlockTransitionsToFinished() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		let blocks = makeBlocks(["A."])
		synth.play(blocks: blocks, voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		mockEngine.fireDidFinish(mockEngine.spoken[0])
		#expect(synth.state == .finished)
	}

	@Test func emptyBlocksLandsInIdle() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		synth.play(blocks: [], voice: makeVoice(), rate: 1.0)
		#expect(mockEngine.spoken.isEmpty)
		#expect(synth.state == .idle)
	}

	// MARK: - Pause / resume

	@Test func pauseTransitionsToPaused() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		synth.play(blocks: makeBlocks(["A.", "B."]), voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		synth.pause()
		mockEngine.fireDidPause(mockEngine.spoken[0])
		#expect(synth.state == .paused(blockIndex: 0, totalBlocks: 2))
		#expect(mockEngine.pauseCount == 1)
	}

	@Test func resumeTransitionsBackToSpeaking() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		synth.play(blocks: makeBlocks(["A.", "B."]), voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		synth.pause()
		mockEngine.fireDidPause(mockEngine.spoken[0])
		synth.resume()
		mockEngine.fireDidContinue(mockEngine.spoken[0])
		#expect(synth.state == .speaking(blockIndex: 0, totalBlocks: 2))
		#expect(mockEngine.continueCount == 1)
	}

	// MARK: - Skip

	@Test func skipForwardCallsStopAndQueuesNextIndex() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		let blocks = makeBlocks(["A.", "B.", "C."])
		synth.play(blocks: blocks, voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		synth.skipForward()
		#expect(mockEngine.stopCount == 1)
		mockEngine.fireDidCancel(mockEngine.spoken[0])
		#expect(mockEngine.spoken.count == 2)
		mockEngine.fireDidStart(mockEngine.spoken[1])
		#expect(synth.state == .speaking(blockIndex: 1, totalBlocks: 3))
	}

	@Test func skipBackwardClampsAtZero() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		let blocks = makeBlocks(["A.", "B."])
		synth.play(blocks: blocks, voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		synth.skipBackward()
		mockEngine.fireDidCancel(mockEngine.spoken[0])
		// Should re-speak block 0 (clamped).
		#expect(mockEngine.spoken.count == 2)
		mockEngine.fireDidStart(mockEngine.spoken[1])
		#expect(synth.state == .speaking(blockIndex: 0, totalBlocks: 2))
	}

	@Test func skipForwardClampsAtLastIndex() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		let blocks = makeBlocks(["A.", "B."])
		synth.play(blocks: blocks, voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		mockEngine.fireDidFinish(mockEngine.spoken[0])
		mockEngine.fireDidStart(mockEngine.spoken[1])
		// We're at the last block; skipForward should re-speak block 1.
		synth.skipForward()
		mockEngine.fireDidCancel(mockEngine.spoken[1])
		guard let last = mockEngine.spoken.last else {
			Issue.record("Expected an utterance to be spoken")
			return
		}
		mockEngine.fireDidStart(last)
		#expect(synth.state == .speaking(blockIndex: 1, totalBlocks: 2))
	}

	@Test func rapidDoubleSkipLandsAtLastSetIndex() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		let blocks = makeBlocks(["A.", "B.", "C.", "D."])
		synth.play(blocks: blocks, voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		synth.skipForward()  // sets pendingAction = .skipTo(1)
		synth.skipForward()  // overwrites to .skipTo(2)
		mockEngine.fireDidCancel(mockEngine.spoken[0])
		guard let last = mockEngine.spoken.last else {
			Issue.record("Expected an utterance to be spoken")
			return
		}
		mockEngine.fireDidStart(last)
		#expect(synth.state == .speaking(blockIndex: 2, totalBlocks: 4))
	}

	// MARK: - Stop

	@Test func stopClearsStateAndUtterances() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		let blocks = makeBlocks(["A.", "B."])
		synth.play(blocks: blocks, voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		synth.stop()
		mockEngine.fireDidCancel(mockEngine.spoken[0])
		#expect(synth.state == .idle)
		#expect(mockEngine.stopCount == 1)
	}

	@Test func stopWhilePausedReturnsToIdle() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		synth.play(blocks: makeBlocks(["A."]), voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		synth.pause()
		mockEngine.fireDidPause(mockEngine.spoken[0])
		synth.stop()
		mockEngine.fireDidCancel(mockEngine.spoken[0])
		#expect(synth.state == .idle)
	}

	// MARK: - Replace mid-playback

	@Test func playWhileSpeakingReplacesUtterances() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		synth.play(blocks: makeBlocks(["A.", "B."]), voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		synth.play(blocks: makeBlocks(["X.", "Y.", "Z."]), voice: makeVoice(), rate: 1.0)
		// The synth should have called stop and queued a replacement; one new speak yet.
		#expect(mockEngine.stopCount == 1)
		mockEngine.fireDidCancel(mockEngine.spoken[0])
		#expect(mockEngine.spoken.count == 2)  // first A + first X
		guard let last = mockEngine.spoken.last else {
			Issue.record("Expected an utterance to be spoken")
			return
		}
		mockEngine.fireDidStart(last)
		#expect(synth.state == .speaking(blockIndex: 0, totalBlocks: 3))
	}

	@Test func playFromIdleAfterFinishedStartsCleanly() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		synth.play(blocks: makeBlocks(["A."]), voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		mockEngine.fireDidFinish(mockEngine.spoken[0])
		#expect(synth.state == .finished)
		synth.play(blocks: makeBlocks(["X.", "Y."]), voice: makeVoice(), rate: 1.0)
		#expect(mockEngine.spoken.count == 2)
		mockEngine.fireDidStart(mockEngine.spoken[1])
		#expect(synth.state == .speaking(blockIndex: 0, totalBlocks: 2))
	}

	// MARK: - Spurious cancel

	@Test func spuriousCancelResetsToIdle() {
		let mockEngine = MockAppleSpeechEngine()
		let synth = AppleSpeechSynth(engine: mockEngine)
		synth.play(blocks: makeBlocks(["A.", "B."]), voice: makeVoice(), rate: 1.0)
		mockEngine.fireDidStart(mockEngine.spoken[0])
		// Fire a cancel without any pending action set by the synth itself.
		mockEngine.fireDidCancel(mockEngine.spoken[0])
		#expect(synth.state == .idle)
	}
}
