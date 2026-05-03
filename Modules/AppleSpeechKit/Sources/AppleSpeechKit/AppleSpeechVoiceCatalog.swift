import Foundation
import AVFoundation
import ArticleSpeech

// MARK: - AppleSpeechVoiceCatalog
//
// Audit notes (last verified 2026-05-02 against macOS 26.4.1):
//
// - User-selectable voice list filters out Apple's "Novelty" category (using
//   the `voiceTraits.isNoveltyVoice` API trait) plus legacy classic-Mac-OS
//   voices identified by the `com.apple.speech.synthesis.voice.` ID prefix.
//   The trait check is forward-compatible (new novelty voices Apple ships
//   are excluded automatically); the prefix check covers older voices
//   (Fred, Junior, Kathy, Ralph) that Apple did not retroactively tag.
//
// - Personal voices (voiceTraits.isPersonalVoice) intentionally pass the
//   filter and are surfaced in the picker with "(Personal)" appended to
//   their displayName.
//
// - Recommended-voice catalog covers en-US and en-GB only and lists voices
//   confirmed to exist at the recommended quality tier on the verification
//   date. Apple has historically deprecated quality tiers across macOS
//   versions; if catalog entries start reporting `isInstalled: false`
//   universally, re-verify the IDs.

public enum AppleSpeechVoiceCatalog {

	/// Returns voices whose locale matches the given language tag as a prefix.
	/// Pass `"en"` for all English variants; pass `"en-US"` to narrow to US English;
	/// pass `""` to return everything.
	public static func installedVoices(matching languageTag: String) -> [SpeechVoice] {
		AVSpeechSynthesisVoice.speechVoices()
			.filter { $0.language.hasPrefix(languageTag) }
			.filter(isUserSelectableVoice)
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
		// Apple's `name` follows a "Name (Quality)" convention for enhanced/
		// premium voices ("Ava (Premium)", "Daniel (Enhanced)") and bare "Name"
		// for compact. We surface quality via SpeechVoice.qualityTier as a
		// structured field, so strip the parenthetical from displayName to
		// avoid redundancy in the voice picker UI (which renders both the
		// name and the quality tier).
		let bareName: String
		if let parenIndex = avSpeechSynthesisVoice.name.firstIndex(of: "(") {
			bareName = String(avSpeechSynthesisVoice.name[..<parenIndex]).trimmingCharacters(in: .whitespaces)
		} else {
			bareName = avSpeechSynthesisVoice.name
		}
		// Personal voices don't carry a quality tier; their qualityTier is
		// .standard but the picker should still distinguish them from system
		// voices. Append "(Personal)" since "Personal" isn't a quality tier
		// covered by SpeechVoice.qualityTier. The `contains("Personal")` guard
		// prevents double-suffixing if Apple ever starts including this token
		// in their `name` field directly.
		let displayName: String
		if avSpeechSynthesisVoice.voiceTraits.contains(.isPersonalVoice)
			&& !bareName.contains("Personal") {
			displayName = "\(bareName) (Personal)"
		} else {
			displayName = bareName
		}
		return SpeechVoice(
			identifier: avSpeechSynthesisVoice.identifier,
			displayName: displayName,
			language: avSpeechSynthesisVoice.language,
			qualityTier: qualityTier,
			gender: gender,
			isInstalled: true
		)
	}

	/// Returns `true` when a voice from `AVSpeechSynthesisVoice.speechVoices()`
	/// should be exposed to users as a selectable speech voice for article
	/// reading. Excludes:
	///
	/// - Voices Apple has tagged as novelty (Bahh, Whisper, Boing, etc.) — these
	///   are character/effect voices unsuitable for content reading. Apple's
	///   `voiceTraits.isNoveltyVoice` flag is the source of truth and is
	///   forward-compatible with future novelty additions.
	///
	/// - Voices using the legacy classic-Mac-OS ID prefix
	///   `com.apple.speech.synthesis.voice.` — Fred, Junior, Kathy, Ralph and
	///   the novelty voices all use this format. Apple has been migrating to
	///   `com.apple.voice.<quality>.<lang>.<Name>` for over a decade and the
	///   legacy prefix is reliably "old, low-quality, robotic" voices.
	///
	/// Personal voices (`voiceTraits.isPersonalVoice`) are intentionally NOT
	/// excluded — they're modern, valuable for accessibility users, and use
	/// modern ID formats that don't trip either filter clause.
	internal static func isUserSelectableVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
		if voice.voiceTraits.contains(.isNoveltyVoice) {
			return false
		}
		if voice.identifier.hasPrefix("com.apple.speech.synthesis.voice.") {
			return false
		}
		return true
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
		// English (US)
		.init(identifier: "com.apple.voice.premium.en-US.Ava",       displayName: "Ava",      gender: .female, language: "en-US", qualityTier: .premium),
		.init(identifier: "com.apple.voice.enhanced.en-US.Samantha", displayName: "Samantha", gender: .female, language: "en-US", qualityTier: .enhanced),
		// English (UK)
		.init(identifier: "com.apple.voice.premium.en-GB.Serena",    displayName: "Serena",   gender: .female, language: "en-GB", qualityTier: .premium),
		.init(identifier: "com.apple.voice.enhanced.en-GB.Kate",     displayName: "Kate",     gender: .female, language: "en-GB", qualityTier: .enhanced),
		.init(identifier: "com.apple.voice.enhanced.en-GB.Daniel",   displayName: "Daniel",   gender: .male,   language: "en-GB", qualityTier: .enhanced),
	]
}
