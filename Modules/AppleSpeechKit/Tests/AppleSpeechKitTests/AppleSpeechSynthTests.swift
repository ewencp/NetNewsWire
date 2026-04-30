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
}
