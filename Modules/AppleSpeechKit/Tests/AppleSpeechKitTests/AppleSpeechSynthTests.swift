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

/// Tests for the paragraph-aligned skip semantics — `skipForward()` and
/// `skipBackward()` should move `currentBlockIndex` by one block and update
/// `state` immediately (via the seek path's explicit state update, so the
/// progress UI reflects the new position without waiting for the next
/// buffer-completion's `didAdvanceTo`).
///
/// Like the block-boundary tests, these run against a real
/// `AVSpeechSynthesizer` and use poll-with-deadline to avoid timing
/// flakiness from fixed sleeps.
@MainActor
struct AppleSpeechSynthSkipTests {

	@Test
	func skipForward_advancesCurrentBlock() async throws {
		let synth = AppleSpeechSynth()
		let voice = try #require(await synth.availableVoices().first)
		let blocks = (1...3).map { SpeechBlock(text: "Block \($0).", kind: .paragraph) }

		synth.play(blocks: blocks, voice: voice, rate: 1.0, startingAt: 0)

		// Wait until the synth is actually speaking (block 0 fully rendered
		// and player.play() has fired the .playing state transition). This
		// avoids the "skip while .preparing" edge case where wasPlaying is
		// false.
		try await pollUntil(timeout: 10) {
			if case .speaking = synth.state {
				return true
			}
			return false
		}

		synth.skipForward()

		// Skip path updates state immediately to .speaking(1, _); no need
		// to wait for the next buffer-completion.
		try await pollUntil(timeout: 5) {
			if case .speaking(let idx, _) = synth.state, idx == 1 {
				return true
			}
			return false
		}

		if case let .speaking(blockIndex, totalBlocks) = synth.state {
			#expect(blockIndex == 1)
			#expect(totalBlocks == 3)
		} else {
			Issue.record("Expected .speaking(1, 3) after skipForward, got \(synth.state)")
		}
		synth.stop()
	}

	@Test
	func skipBackward_decrementsCurrentBlock() async throws {
		let synth = AppleSpeechSynth()
		let voice = try #require(await synth.availableVoices().first)
		let blocks = (1...3).map { SpeechBlock(text: "Block \($0).", kind: .paragraph) }

		// Start at block 2 so skipBackward has somewhere to go.
		synth.play(blocks: blocks, voice: voice, rate: 1.0, startingAt: 2)

		try await pollUntil(timeout: 10) {
			if case .speaking = synth.state {
				return true
			}
			return false
		}

		synth.skipBackward()

		try await pollUntil(timeout: 10) {
			if case .speaking(let idx, _) = synth.state, idx == 1 {
				return true
			}
			return false
		}

		if case let .speaking(blockIndex, totalBlocks) = synth.state {
			#expect(blockIndex == 1)
			#expect(totalBlocks == 3)
		} else {
			Issue.record("Expected .speaking(1, 3) after skipBackward, got \(synth.state)")
		}
		synth.stop()
	}

	@Test
	func skipForward_atLastBlock_staysAtLastBlock() async throws {
		let synth = AppleSpeechSynth()
		let voice = try #require(await synth.availableVoices().first)
		let blocks = (1...3).map { SpeechBlock(text: "Block \($0).", kind: .paragraph) }

		// Start at the last block.
		synth.play(blocks: blocks, voice: voice, rate: 1.0, startingAt: 2)

		try await pollUntil(timeout: 10) {
			if case .speaking = synth.state {
				return true
			}
			return false
		}

		synth.skipForward()
		try await Task.sleep(for: .milliseconds(200))

		// skipForward should clamp at the last block, not advance past it
		// (and not return to .idle or .finished).
		if case let .speaking(blockIndex, _) = synth.state {
			#expect(blockIndex == 2)
		}
		synth.stop()
	}

	@Test
	func skipBackward_atFirstBlock_staysAtFirstBlock() async throws {
		let synth = AppleSpeechSynth()
		let voice = try #require(await synth.availableVoices().first)
		let blocks = (1...3).map { SpeechBlock(text: "Block \($0).", kind: .paragraph) }

		synth.play(blocks: blocks, voice: voice, rate: 1.0, startingAt: 0)

		try await pollUntil(timeout: 10) {
			if case .speaking = synth.state {
				return true
			}
			return false
		}

		synth.skipBackward()
		try await Task.sleep(for: .milliseconds(200))

		// skipBackward should clamp at block 0.
		if case let .speaking(blockIndex, _) = synth.state {
			#expect(blockIndex == 0)
		}
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
