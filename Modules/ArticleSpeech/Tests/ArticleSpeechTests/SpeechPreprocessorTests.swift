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

	@Test func headingsCarryLevel() {
		let result = SpeechPreprocessor.preprocess(
			html: "<h2>Topic</h2><p>Body.</p>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [
			.heading(level: 2, "Topic"),
			.paragraph("Body."),
		])
	}

	@Test func headingsAtAllLevels() {
		for level in 1...6 {
			let html = "<h\(level)>Section</h\(level)>"
			let result = SpeechPreprocessor.preprocess(
				html: html,
				articleID: "a1",
				title: nil,
				language: nil
			)
			#expect(result.segments == [.heading(level: level, "Section")])
		}
	}

	@Test func blockquotePreservesText() {
		let result = SpeechPreprocessor.preprocess(
			html: "<blockquote>Quote text.</blockquote>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [.blockQuote("Quote text.")])
	}

	@Test func inlineFormattingTagsAreStripped() {
		let result = SpeechPreprocessor.preprocess(
			html: "<p>Hello <em>brave</em> <strong>new</strong> <a href=\"x\">world</a>.</p>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [.paragraph("Hello brave new world.")])
	}

	@Test func scriptAndStyleTagsAreRemovedEntirely() {
		let result = SpeechPreprocessor.preprocess(
			html: "<script>alert('x')</script><style>p{color:red}</style><p>Body.</p>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [.paragraph("Body.")])
	}

	@Test func unorderedListItemsAtDepthZero() {
		let result = SpeechPreprocessor.preprocess(
			html: "<ul><li>A</li><li>B</li></ul>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [
			.listItem(depth: 0, ordering: .unordered, "A"),
			.listItem(depth: 0, ordering: .unordered, "B"),
		])
	}

	@Test func orderedListItemsCarryIndex() {
		let result = SpeechPreprocessor.preprocess(
			html: "<ol><li>First</li><li>Second</li><li>Third</li></ol>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [
			.listItem(depth: 0, ordering: .ordered(index: 1), "First"),
			.listItem(depth: 0, ordering: .ordered(index: 2), "Second"),
			.listItem(depth: 0, ordering: .ordered(index: 3), "Third"),
		])
	}

	@Test func nestedListItemsTrackDepth() {
		let result = SpeechPreprocessor.preprocess(
			html: "<ul><li>Outer<ul><li>Inner</li></ul></li><li>Sibling</li></ul>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [
			.listItem(depth: 0, ordering: .unordered, "Outer"),
			.listItem(depth: 1, ordering: .unordered, "Inner"),
			.listItem(depth: 0, ordering: .unordered, "Sibling"),
		])
	}

	@Test func paragraphsAndListsInterleaveInDocumentOrder() {
		let result = SpeechPreprocessor.preprocess(
			html: "<p>Before.</p><ul><li>A</li><li>B</li></ul><p>After.</p>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [
			.paragraph("Before."),
			.listItem(depth: 0, ordering: .unordered, "A"),
			.listItem(depth: 0, ordering: .unordered, "B"),
			.paragraph("After."),
		])
	}
}
