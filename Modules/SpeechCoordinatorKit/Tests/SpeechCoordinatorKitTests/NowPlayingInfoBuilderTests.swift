import Testing
import Foundation
import MediaPlayer
import ArticleSpeech
@testable import SpeechCoordinatorKit

struct NowPlayingInfoBuilderTests {

	private func sampleMetadata() -> SpeechItemMetadata {
		SpeechItemMetadata(
			articleID: "id-1",
			title: "Hello World",
			feedName: "Example Feed",
			imageURL: URL(string: "https://example.com/img.png"),
			wordCount: 0
		)
	}

	@Test func includesTitleAndArtist() {
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(),
			state: .speaking(blockIndex: 0, totalBlocks: 4),
			elapsedSeconds: 0,
			totalDurationSeconds: 120
		)
		#expect(dict[MPMediaItemPropertyTitle] as? String == "Hello World")
		#expect(dict[MPMediaItemPropertyArtist] as? String == "Example Feed")
	}

	@Test func playbackRateIsOneWhenSpeaking() {
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(),
			state: .speaking(blockIndex: 0, totalBlocks: 4),
			elapsedSeconds: 0,
			totalDurationSeconds: 120
		)
		#expect(dict[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0)
	}

	@Test func playbackRateIsZeroWhenPaused() {
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(),
			state: .paused(blockIndex: 1, totalBlocks: 4),
			elapsedSeconds: 30,
			totalDurationSeconds: 120
		)
		#expect(dict[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0.0)
	}

	@Test func durationAndElapsedPassThrough() {
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(),
			state: .speaking(blockIndex: 2, totalBlocks: 4),
			elapsedSeconds: 42.0,
			totalDurationSeconds: 300.0
		)
		#expect(dict[MPMediaItemPropertyPlaybackDuration] as? Double == 300.0)
		#expect(dict[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 42.0)
	}

	@Test func nilFeedNameOmitsArtistKey() {
		let m = SpeechItemMetadata(articleID: "id", title: "T", feedName: nil, imageURL: nil, wordCount: 0)
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: m,
			state: .speaking(blockIndex: 0, totalBlocks: 1),
			elapsedSeconds: 0,
			totalDurationSeconds: 0
		)
		#expect(dict[MPMediaItemPropertyArtist] == nil)
	}

	@Test func zeroDurationAndElapsedAreFiniteAndZero() {
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(),
			state: .preparing,
			elapsedSeconds: 0,
			totalDurationSeconds: 0
		)
		#expect((dict[MPMediaItemPropertyPlaybackDuration] as? Double) == 0)
		#expect((dict[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double) == 0)
		#expect(dict[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0.0)
	}
}
