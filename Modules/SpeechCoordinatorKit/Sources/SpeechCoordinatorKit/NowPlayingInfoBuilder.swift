import Foundation
import MediaPlayer
import ArticleSpeech

/// Builds the dictionary written to `MPNowPlayingInfoCenter.default().nowPlayingInfo`.
///
/// Pure function: takes the playing-item metadata, current synth state, and
/// actual sample-time-derived elapsed + total duration; returns a dictionary
/// keyed by `MPMediaItemProperty*` and `MPNowPlayingInfoProperty*` constants.
/// Artwork is **not** populated here — the iOS presenter manages artwork
/// (with the app-icon fallback) and merges it into the dict before writing
/// to `MPNowPlayingInfoCenter`.
///
/// Pre-PCM-pipeline this used a wpm constant to *estimate* duration from
/// the article's word count and a block-fraction to estimate elapsed.
/// Now that `AudioBufferPlayer.currentSampleTime` reports actual frames
/// rendered, `AppleSpeechSynth.elapsedSeconds` and `.durationSeconds`
/// give accurate values straight from the player; this builder just
/// passes them through.
public enum NowPlayingInfoBuilder {

	public static func buildInfo(
		metadata: SpeechItemMetadata,
		state: SpeechSynthState,
		elapsedSeconds: Double,
		totalDurationSeconds: Double
	) -> [String: Any] {
		var dict: [String: Any] = [:]

		dict[MPMediaItemPropertyTitle] = metadata.title
		if let feedName = metadata.feedName {
			dict[MPMediaItemPropertyArtist] = feedName
		}

		dict[MPMediaItemPropertyPlaybackDuration] = totalDurationSeconds
		dict[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedSeconds
		dict[MPNowPlayingInfoPropertyPlaybackRate] = isSpeaking(state) ? 1.0 : 0.0

		return dict
	}

	private static func isSpeaking(_ state: SpeechSynthState) -> Bool {
		if case .speaking = state {
			return true
		}
		return false
	}
}
