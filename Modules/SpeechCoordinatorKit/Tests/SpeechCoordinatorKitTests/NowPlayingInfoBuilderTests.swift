import Testing
import Foundation
import MediaPlayer
import ArticleSpeech
@testable import SpeechCoordinatorKit

struct NowPlayingInfoBuilderTests {

	private func sampleMetadata(wordCount: Int = 360) -> SpeechItemMetadata {
		SpeechItemMetadata(
			articleID: "id-1",
			title: "Hello World",
			feedName: "Example Feed",
			imageURL: URL(string: "https://example.com/img.png"),
			wordCount: wordCount
		)
	}

	@Test func includesTitleAndArtist() {
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(),
			state: .speaking(blockIndex: 0, totalBlocks: 4),
			wordsPerMinute: 180
		)
		#expect(dict[MPMediaItemPropertyTitle] as? String == "Hello World")
		#expect(dict[MPMediaItemPropertyArtist] as? String == "Example Feed")
	}

	@Test func playbackRateIsOneWhenSpeaking() {
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(),
			state: .speaking(blockIndex: 0, totalBlocks: 4),
			wordsPerMinute: 180
		)
		#expect(dict[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0)
	}

	@Test func playbackRateIsZeroWhenPaused() {
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(),
			state: .paused(blockIndex: 1, totalBlocks: 4),
			wordsPerMinute: 180
		)
		#expect(dict[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0.0)
	}

	@Test func durationFromWordCount() {
		// 360 words at 180 wpm = 2 minutes = 120 seconds
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(wordCount: 360),
			state: .speaking(blockIndex: 0, totalBlocks: 4),
			wordsPerMinute: 180
		)
		#expect(dict[MPMediaItemPropertyPlaybackDuration] as? Double == 120.0)
	}

	@Test func elapsedIsBlockFractionTimesDuration() {
		// 2/4 of duration = 60 seconds
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(wordCount: 360),
			state: .speaking(blockIndex: 2, totalBlocks: 4),
			wordsPerMinute: 180
		)
		#expect(dict[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 60.0)
	}

	@Test func nilFeedNameOmitsArtistKey() {
		let m = SpeechItemMetadata(articleID: "id", title: "T", feedName: nil, imageURL: nil, wordCount: 0)
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: m,
			state: .speaking(blockIndex: 0, totalBlocks: 1),
			wordsPerMinute: 180
		)
		#expect(dict[MPMediaItemPropertyArtist] == nil)
	}

	@Test func nonProgressStateGivesZeroElapsedAndNoCrash() {
		let dict = NowPlayingInfoBuilder.buildInfo(
			metadata: sampleMetadata(wordCount: 360),
			state: .preparing,
			wordsPerMinute: 180
		)
		if let elapsed = dict[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double {
			#expect(elapsed.isFinite)
			#expect(elapsed == 0.0)
		}
	}
}
