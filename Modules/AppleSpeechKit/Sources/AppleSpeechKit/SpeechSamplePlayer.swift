import Foundation
import AVFoundation
import ArticleSpeech

/// One-off AVSpeechSynthesizer used by Settings to preview voices and rates
/// without affecting `SpeechCoordinator`'s active playback.
@MainActor
public final class SpeechSamplePlayer {

	public static let shared = SpeechSamplePlayer()

	public static let sampleSentence = NSLocalizedString(
		"This is a sample of the selected voice.",
		comment: "Sample sentence spoken when previewing a TTS voice in settings."
	)

	private let avSpeechSynthesizer = AVSpeechSynthesizer()

	private init() {}

	public func playSample(voice: SpeechVoice, rateMultiplier: Float) {
		avSpeechSynthesizer.stopSpeaking(at: .immediate)
		let avSpeechUtterance = AVSpeechUtterance(string: Self.sampleSentence)
		avSpeechUtterance.voice = AVSpeechSynthesisVoice(identifier: voice.identifier)
			?? AVSpeechSynthesisVoice(language: voice.language)
		avSpeechUtterance.rate = mapRate(rateMultiplier)
		avSpeechSynthesizer.speak(avSpeechUtterance)
	}

	public func stop() {
		avSpeechSynthesizer.stopSpeaking(at: .immediate)
	}

	private func mapRate(_ multiplier: Float) -> Float {
		// Mirrors AppleSpeechSynth.mapRate so previews match real playback.
		let avSpeechDefault = AVSpeechUtteranceDefaultSpeechRate
		let perStep: Float = 0.15
		let raw = avSpeechDefault + (multiplier - 1.0) * perStep
		return min(max(raw, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
	}
}
