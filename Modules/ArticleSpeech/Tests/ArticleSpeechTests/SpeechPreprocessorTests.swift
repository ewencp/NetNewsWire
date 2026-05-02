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
		#expect(result.segments == [.paragraph("Hello\u{00A0}&\u{00A0}world.")])
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

	@Test func curlyQuoteEntitiesAreDecoded() {
		let result = SpeechPreprocessor.preprocess(
			html: "<p>He said &ldquo;hello&rdquo; and &lsquo;world&rsquo;.</p>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [.paragraph("He said \u{201C}hello\u{201D} and \u{2018}world\u{2019}.")])
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

	@Test func standaloneImageProducesImageSegmentInOrder() {
		let result = SpeechPreprocessor.preprocess(
			html: "<p>Before.</p><img src=\"x.jpg\" alt=\"A cat\"><p>After.</p>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [
			.paragraph("Before."),
			.image(SpeechContent.ImageDescriptor(src: "x.jpg", alt: "A cat", caption: nil)),
			.paragraph("After."),
		])
	}

	@Test func figureWithCaptionProducesFigureSegment() {
		let html = "<figure><img src=\"f.jpg\" alt=\"Fig\"><figcaption>The caption.</figcaption></figure>"
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments.count == 1)
		guard case .figure(let descriptor) = result.segments.first else {
			Issue.record("Expected a figure segment")
			return
		}
		#expect(descriptor.src == "f.jpg")
		#expect(descriptor.alt == "Fig")
		#expect(descriptor.caption == "The caption.")
	}

	@Test func figureWithImgInsideDoesNotProduceSeparateImageSegment() {
		let html = "<p>Before.</p><figure><img src=\"f.jpg\" alt=\"Fig\"></figure><p>After.</p>"
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments.count == 3)
		#expect(result.segments[0] == .paragraph("Before."))
		if case .figure = result.segments[1] {} else { Issue.record("Expected figure at index 1") }
		#expect(result.segments[2] == .paragraph("After."))
	}

	@Test func codeBlockExtractsLanguageAndContent() {
		let html = "<pre><code class=\"language-swift\">let x = 1</code></pre>"
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments == [.codeBlock(language: "swift", content: "let x = 1")])
	}

	@Test func codeBlockWithoutLanguageHasNilLanguage() {
		let html = "<pre><code>let x = 1</code></pre>"
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments == [.codeBlock(language: nil, content: "let x = 1")])
	}

	@Test func paragraphsFiguresAndCodeInterleaveInDocumentOrder() {
		let html = """
		<p>Intro.</p><figure><img src="f.jpg" alt="A"><figcaption>Cap.</figcaption></figure>\
		<p>Middle.</p><pre><code class="language-swift">let x = 1</code></pre><p>End.</p>
		"""
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments.count == 5)
		#expect(result.segments[0] == .paragraph("Intro."))
		if case .figure = result.segments[1] {} else { Issue.record("Expected figure at index 1") }
		#expect(result.segments[2] == .paragraph("Middle."))
		#expect(result.segments[3] == .codeBlock(language: "swift", content: "let x = 1"))
		#expect(result.segments[4] == .paragraph("End."))
	}

	@Test func tableWithRowsAndColumnsCountsBoth() {
		let html = """
		<table>\
		<tr><th>A</th><th>B</th><th>C</th></tr>\
		<tr><td>1</td><td>2</td><td>3</td></tr>\
		<tr><td>4</td><td>5</td><td>6</td></tr>\
		</table>
		"""
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments == [.table(rowCount: 3, columnCount: 3)])
	}

	@Test func emptyTableProducesNilCounts() {
		let result = SpeechPreprocessor.preprocess(
			html: "<table></table>",
			articleID: "a1",
			title: nil,
			language: nil
		)
		#expect(result.segments == [.table(rowCount: nil, columnCount: nil)])
	}

	@Test func paragraphsAndTablesInterleaveInDocumentOrder() {
		let html = """
		<p>Before.</p>\
		<table><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>\
		<p>After.</p>
		"""
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments == [
			.paragraph("Before."),
			.table(rowCount: 2, columnCount: 2),
			.paragraph("After."),
		])
	}

	// MARK: - Tidemark v1.0 / HTML5-permissive output
	//
	// Tidemark's CommonMark renderer (used by SummaryPostprocessor) emits
	// opening <p> and <li> tags without matching close tags; web views infer
	// the closes at the next block-level element. The preprocessor must
	// extract the same segments from this style of input as from the strict
	// XHTML-style input the rest of the codebase produces.

	@Test func unclosedParagraphsSeparatedByBlankLines() {
		let html = "<p>First.\n\n<p>Second.\n\n<p>Third."
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments == [
			.paragraph("First."),
			.paragraph("Second."),
			.paragraph("Third."),
		])
	}

	@Test func unclosedParagraphsMixedWithClosedHeader() {
		let html = "<p>Intro.\n\n<h3>Heading</h3>\n\n<p>After."
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments == [
			.paragraph("Intro."),
			.heading(level: 3, "Heading"),
			.paragraph("After."),
		])
	}

	@Test func unclosedListItemsInsideClosedList() {
		let html = "<ul>\n<li><p>Apple.\n<li><p>Banana.\n</ul>"
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments == [
			.listItem(depth: 0, ordering: .unordered, "Apple."),
			.listItem(depth: 0, ordering: .unordered, "Banana."),
		])
	}

	@Test func unclosedOrderedListItemsAreNumbered() {
		let html = "<ol>\n<li><p>First.\n<li><p>Second.\n<li><p>Third.\n</ol>"
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments == [
			.listItem(depth: 0, ordering: .ordered(index: 1), "First."),
			.listItem(depth: 0, ordering: .ordered(index: 2), "Second."),
			.listItem(depth: 0, ordering: .ordered(index: 3), "Third."),
		])
	}

	@Test func tidemarkStyleParagraphsAndListInterleave() {
		// Realistic LLM-summary output after Tidemark conversion: paragraphs
		// of text, then a bullet list, then a closing paragraph.
		let html = """
		<p>The article discusses three points.

		<ul>
		<li><p>First point.
		<li><p>Second point.
		<li><p>Third point.
		</ul>

		<p>It concludes with a recommendation.
		"""
		let result = SpeechPreprocessor.preprocess(html: html, articleID: "a1", title: nil, language: nil)
		#expect(result.segments == [
			.paragraph("The article discusses three points."),
			.listItem(depth: 0, ordering: .unordered, "First point."),
			.listItem(depth: 0, ordering: .unordered, "Second point."),
			.listItem(depth: 0, ordering: .unordered, "Third point."),
			.paragraph("It concludes with a recommendation."),
		])
	}
}
