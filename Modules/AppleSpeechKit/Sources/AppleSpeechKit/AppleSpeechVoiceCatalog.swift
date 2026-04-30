import Foundation
import AVFoundation
import ArticleSpeech

public enum AppleSpeechVoiceCatalog {

	/// Returns voices whose locale matches the given language tag as a prefix.
	/// Pass `"en"` for all English variants; pass `"en-US"` to narrow to US English;
	/// pass `""` to return everything.
	public static func installedVoices(matching languageTag: String) -> [SpeechVoice] {
		AVSpeechSynthesisVoice.speechVoices()
			.filter { $0.language.hasPrefix(languageTag) }
			.map(toSpeechVoice)
			.sorted { left, right in
				if left.qualityTier != right.qualityTier {
					return left.qualityTier > right.qualityTier
				}
				return left.displayName < right.displayName
			}
	}

	public static func recommendedVoices(matching languageTag: String) -> [SpeechVoice] {
		let installedIDs = Set(AVSpeechSynthesisVoice.speechVoices().map(\.identifier))
		return staticRecommendedCatalog
			.filter { $0.language.hasPrefix(languageTag) }
			.map { rec in
				SpeechVoice(
					identifier: rec.identifier,
					displayName: rec.displayName,
					language: rec.language,
					qualityTier: rec.qualityTier,
					gender: rec.gender,
					isInstalled: installedIDs.contains(rec.identifier)
				)
			}
	}

	public static var systemDefault: SpeechVoice {
		if let defaultID = UserDefaults.standard.string(forKey: SpeechDefaults.voiceIdentifierKey),
		   let avSpeechSynthesisVoice = AVSpeechSynthesisVoice(identifier: defaultID) {
			return toSpeechVoice(avSpeechSynthesisVoice)
		}
		let language = primaryLanguageTag
		if let avSpeechSynthesisVoice = AVSpeechSynthesisVoice(language: language) {
			return toSpeechVoice(avSpeechSynthesisVoice)
		}
		// Last resort: take the first installed voice.
		if let any = AVSpeechSynthesisVoice.speechVoices().first {
			return toSpeechVoice(any)
		}
		// Truly desperate fallback (should never hit on a real device).
		return SpeechVoice(
			identifier: "com.apple.speech.synthesis.voice.Alex",
			displayName: "Alex",
			language: "en-US",
			qualityTier: .standard,
			gender: .male,
			isInstalled: false
		)
	}

	public static var primaryLanguageTag: String {
		Locale.current.language.languageCode?.identifier ?? "en"
	}

	// MARK: - Internal mapping helpers

	internal static func toSpeechVoice(_ avSpeechSynthesisVoice: AVSpeechSynthesisVoice) -> SpeechVoice {
		let qualityTier: SpeechVoice.QualityTier
		switch avSpeechSynthesisVoice.quality {
		case .premium:  qualityTier = .premium
		case .enhanced: qualityTier = .enhanced
		default:        qualityTier = .standard
		}
		let gender: VoiceGender
		switch avSpeechSynthesisVoice.gender {
		case .female: gender = .female
		case .male:   gender = .male
		default:      gender = .unspecified
		}
		return SpeechVoice(
			identifier: avSpeechSynthesisVoice.identifier,
			displayName: avSpeechSynthesisVoice.name,
			language: avSpeechSynthesisVoice.language,
			qualityTier: qualityTier,
			gender: gender,
			isInstalled: true
		)
	}

	// MARK: - Static recommendation catalog

	internal struct RecommendedVoice {
		let identifier: String
		let displayName: String
		let gender: VoiceGender
		let language: String
		let qualityTier: SpeechVoice.QualityTier
	}

	/// Best-effort identifiers; verify against `AVSpeechSynthesisVoice.speechVoices()`
	/// at integration time and update if Apple has renamed/removed any.
	internal static let staticRecommendedCatalog: [RecommendedVoice] = [
		// English (US) — premium
		.init(identifier: "com.apple.voice.premium.en-US.Ava",   displayName: "Ava (Premium)",   gender: .female, language: "en-US", qualityTier: .premium),
		.init(identifier: "com.apple.voice.premium.en-US.Evan",  displayName: "Evan (Premium)",  gender: .male,   language: "en-US", qualityTier: .premium),
		// English (US) — enhanced
		.init(identifier: "com.apple.voice.enhanced.en-US.Samantha", displayName: "Samantha (Enhanced)", gender: .female, language: "en-US", qualityTier: .enhanced),
		.init(identifier: "com.apple.voice.enhanced.en-US.Alex",     displayName: "Alex (Enhanced)",     gender: .male,   language: "en-US", qualityTier: .enhanced),
		// English (UK) — premium
		.init(identifier: "com.apple.voice.premium.en-GB.Serena", displayName: "Serena (UK, Premium)", gender: .female, language: "en-GB", qualityTier: .premium),
		.init(identifier: "com.apple.voice.premium.en-GB.Oliver", displayName: "Oliver (UK, Premium)", gender: .male,   language: "en-GB", qualityTier: .premium),
		// English (UK) — enhanced
		.init(identifier: "com.apple.voice.enhanced.en-GB.Kate",    displayName: "Kate (UK, Enhanced)",  gender: .female, language: "en-GB", qualityTier: .enhanced),
		.init(identifier: "com.apple.voice.enhanced.en-GB.Daniel",  displayName: "Daniel (UK, Enhanced)", gender: .male,   language: "en-GB", qualityTier: .enhanced),
	]
}
