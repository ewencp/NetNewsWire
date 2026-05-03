import Foundation
import MediaPlayer
import ArticleSpeech

/// Builds the dictionary written to `MPNowPlayingInfoCenter.default().nowPlayingInfo`.
///
/// Pure function: takes the playing-item metadata, current synth state, and a
/// rate-to-wpm constant; returns a dictionary keyed by `MPMediaItemProperty*`
/// and `MPNowPlayingInfoProperty*` constants. Artwork is **not** populated
/// here — the iOS presenter manages artwork (with the app-icon fallback) and
/// merges it into the dict before writing to `MPNowPlayingInfoCenter`.
public enum NowPlayingInfoBuilder {

	public static func buildInfo(
		metadata: SpeechItemMetadata,
		state: SpeechSynthState,
		wordsPerMinute: Double
	) -> [String: Any] {
		var dict: [String: Any] = [:]

		dict[MPMediaItemPropertyTitle] = metadata.title
		if let feedName = metadata.feedName {
			dict[MPMediaItemPropertyArtist] = feedName
		}

		let duration = wordsPerMinute > 0
			? Double(metadata.wordCount) / wordsPerMinute * 60.0
			: 0.0
		dict[MPMediaItemPropertyPlaybackDuration] = duration

		let (blockIndex, totalBlocks, isSpeaking) = blockProgress(from: state)
		let elapsed: Double
		if totalBlocks > 0 {
			elapsed = Double(blockIndex) / Double(totalBlocks) * duration
		} else {
			elapsed = 0.0
		}
		dict[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed

		dict[MPNowPlayingInfoPropertyPlaybackRate] = isSpeaking ? 1.0 : 0.0

		return dict
	}

	private static func blockProgress(from state: SpeechSynthState) -> (Int, Int, Bool) {
		switch state {
		case .speaking(let blockIndex, let totalBlocks):
			return (blockIndex, totalBlocks, true)
		case .paused(let blockIndex, let totalBlocks):
			return (blockIndex, totalBlocks, false)
		default:
			return (0, 0, false)
		}
	}
}
