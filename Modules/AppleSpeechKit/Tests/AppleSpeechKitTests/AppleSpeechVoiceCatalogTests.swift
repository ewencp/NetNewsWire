import Testing
import Foundation
import AVFoundation
import ArticleSpeech
@testable import AppleSpeechKit

struct AppleSpeechVoiceCatalogTests {

	@Test func primaryLanguageTagIsNonEmpty() {
		let tag = AppleSpeechVoiceCatalog.primaryLanguageTag
		#expect(!tag.isEmpty)
	}

	@Test func installedVoicesFiltersByLanguagePrefix() {
		let englishVoices = AppleSpeechVoiceCatalog.installedVoices(matching: "en")
		// Every system has at least one English voice; we just check the filter applied.
		#expect(englishVoices.allSatisfy { $0.language.hasPrefix("en") })
	}

	@Test func installedVoicesEmptyMatchReturnsAllOrMore() {
		let allVoices = AppleSpeechVoiceCatalog.installedVoices(matching: "")
		let englishVoices = AppleSpeechVoiceCatalog.installedVoices(matching: "en")
		// With prefix "", every voice has-prefix the empty string.
		#expect(allVoices.count >= englishVoices.count)
	}

	@Test func recommendedVoicesIncludeEntries() {
		let recommended = AppleSpeechVoiceCatalog.recommendedVoices(matching: "en-US")
		// At least one en-US recommendation should be in the catalog (installed or not).
		#expect(!recommended.isEmpty)
		#expect(recommended.allSatisfy { $0.language.hasPrefix("en-US") })
	}

	@Test func systemDefaultIsValid() {
		let defaultVoice = AppleSpeechVoiceCatalog.systemDefault
		#expect(!defaultVoice.identifier.isEmpty)
		#expect(!defaultVoice.language.isEmpty)
	}

	@Test func installedVoicesExcludesNoveltyVoices() {
		let noveltyIDs = Set(
			AVSpeechSynthesisVoice.speechVoices()
				.filter { $0.voiceTraits.contains(.isNoveltyVoice) }
				.map(\.identifier)
		)
		// Sanity: any modern macOS install ships novelty voices stock-installed.
		// If this assertion fails, the filter test below would be vacuous, so
		// it's the first signal that the test environment is unusual.
		#expect(!noveltyIDs.isEmpty, "Expected stock macOS to ship novelty voices for filter verification")

		let installedIDs = Set(AppleSpeechVoiceCatalog.installedVoices(matching: "").map(\.identifier))
		#expect(installedIDs.intersection(noveltyIDs).isEmpty)
	}

	@Test func installedVoicesExcludesLegacyPrefixVoices() {
		let installed = AppleSpeechVoiceCatalog.installedVoices(matching: "")
		#expect(installed.allSatisfy { !$0.identifier.hasPrefix("com.apple.speech.synthesis.voice.") })
	}

	@Test func installedVoiceDisplayNamesOmitQualityQualifier() {
		let voices = AppleSpeechVoiceCatalog.installedVoices(matching: "")
		for v in voices {
			#expect(!v.displayName.contains("(Enhanced)"),
					"displayName '\(v.displayName)' for \(v.identifier) should not contain '(Enhanced)'")
			#expect(!v.displayName.contains("(Premium)"),
					"displayName '\(v.displayName)' for \(v.identifier) should not contain '(Premium)'")
		}
	}
}
