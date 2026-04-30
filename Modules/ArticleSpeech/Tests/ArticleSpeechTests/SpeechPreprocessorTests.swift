import Testing
import Foundation
@testable import ArticleSpeech

struct SpeechPreprocessorTests {

	@Test func emptyInputProducesNoSegments() {
		let result = SpeechPreprocessor.preprocess(
			html: "",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments.isEmpty)
		#expect(result.sourceArticleID == "a1")
	}

	@Test func singleParagraphProducesParagraphSegment() {
		let result = SpeechPreprocessor.preprocess(
			html: "<p>Hello.</p>",
			articleID: "a1",
			title: "Title",
			language: "en"
		)
		#expect(result.segments == [.paragraph("Hello.")])
		#expect(result.title == "Title")
		#expect(result.language == "en")
	}

	@Test func multipleParagraphsPreserveOrder() {
		let result = SpeechPreprocessor.preprocess(
			html: "<p>First.</p><p>Second.</p>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [.paragraph("First."), .paragraph("Second.")])
	}

	@Test func htmlEntitiesAreDecoded() {
		let result = SpeechPreprocessor.preprocess(
			html: "<p>Hello&nbsp;&amp;&nbsp;world.</p>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [.paragraph("Hello & world.")])
	}

	@Test func numericEntitiesAreDecoded() {
		let result = SpeechPreprocessor.preprocess(
			html: "<p>Caf&#233; &#x2014; bistro.</p>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [.paragraph("Café — bistro.")])
	}
}
