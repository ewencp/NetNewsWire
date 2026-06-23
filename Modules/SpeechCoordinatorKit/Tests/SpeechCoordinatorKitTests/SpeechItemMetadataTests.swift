import Testing
import Foundation
@testable import SpeechCoordinatorKit

struct SpeechItemMetadataTests {

	@Test func equalityHoldsForIdenticalValues() {
		let a = SpeechItemMetadata(
			articleID: "id-1",
			title: "Title",
			feedName: "Feed",
			imageURL: URL(string: "https://example.com/img.png"),
			wordCount: 100
		)
		let b = SpeechItemMetadata(
			articleID: "id-1",
			title: "Title",
			feedName: "Feed",
			imageURL: URL(string: "https://example.com/img.png"),
			wordCount: 100
		)
		#expect(a == b)
	}

	@Test func equalityFailsForDifferingArticleID() {
		let a = SpeechItemMetadata(articleID: "id-1", title: "T", feedName: nil, imageURL: nil, wordCount: 0)
		let b = SpeechItemMetadata(articleID: "id-2", title: "T", feedName: nil, imageURL: nil, wordCount: 0)
		#expect(a != b)
	}

	@Test func optionalsRoundTrip() {
		let m = SpeechItemMetadata(articleID: "id", title: "T", feedName: nil, imageURL: nil, wordCount: 42)
		#expect(m.feedName == nil)
		#expect(m.imageURL == nil)
		#expect(m.wordCount == 42)
	}
}
