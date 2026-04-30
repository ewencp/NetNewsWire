import Testing
import Foundation
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
}
