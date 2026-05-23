import Testing
import Foundation
import AVFoundation
import ArticleSpeech
@testable import AppleSpeechKit

/// Tests that exercise `AppleSpeechSynth`'s block-boundary tracking using a
/// real `AVSpeechSynthesizer` (no mock — the engine abstraction was retired
/// alongside the write-based PCM pipeline). These run via `swift test`,
/// which is the stable Swift Testing runner for TextToSpeech-touching code.
///
/// Timing: synthesis-rendering durations vary by voice and host load. We
/// poll for the awaited condition with a generous deadline rather than
/// relying on a fixed sleep, so the tests aren't timing-flaky.
@MainActor
struct AppleSpeechSynthBlockBoundaryTests {

	@Test
	func play_singleBlock_setsBlockBoundaryAtZero() async throws {
		let synth = AppleSpeechSynth()
		let voice = try #require(await synth.availableVoices().first)
		let block = SpeechBlock(text: "Hello world.", kind: .paragraph)

		synth.play(blocks: [block], voice: voice, rate: 1.0, startingAt: 0)

		try await pollUntil(timeout: 10) {
			synth.blockBoundarySampleTime(forBlockIndex: 0) != nil
		}

		#expect(synth.blockBoundarySampleTime(forBlockIndex: 0) == 0)
		synth.stop()
	}

	@Test
	func play_twoBlocks_secondBlockBoundaryAfterFirstBlocksFrames() async throws {
		let synth = AppleSpeechSynth()
		let voice = try #require(await synth.availableVoices().first)
		let block1 = SpeechBlock(text: "First paragraph.", kind: .paragraph)
		let block2 = SpeechBlock(text: "Second paragraph.", kind: .paragraph)

		synth.play(blocks: [block1, block2], voice: voice, rate: 1.0, startingAt: 0)

		// Wait for the prefetch-ahead window to render block 1 too.
		try await pollUntil(timeout: 15) {
			synth.blockBoundarySampleTime(forBlockIndex: 0) != nil
				&& synth.blockBoundarySampleTime(forBlockIndex: 1) != nil
		}

		let b0 = synth.blockBoundarySampleTime(forBlockIndex: 0)
		let b1 = synth.blockBoundarySampleTime(forBlockIndex: 1)
		#expect(b0 == 0)
		if let b1 { #expect(b1 > 0) }
		synth.stop()
	}
}

/// Poll-with-deadline helper. Returns when `condition` becomes true, or
/// throws if `timeout` seconds elapse first. Polls every 50ms.
@MainActor
private func pollUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
	let deadline = Date().addingTimeInterval(timeout)
	while Date() < deadline {
		if condition() { return }
		try await Task.sleep(for: .milliseconds(50))
	}
	if !condition() {
		throw PollTimeout()
	}
}

private struct PollTimeout: Error {}
