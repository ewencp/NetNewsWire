import Testing
@testable import ArticleAI

struct ArticlePreprocessorTests {

	@Test func stripsScriptAndStyleTags() {
		let html = "<p>Hello</p><script>alert('x')</script><style>.foo{}</style><p>World</p>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(!result.markdownText.contains("alert"))
		#expect(!result.markdownText.contains(".foo"))
		#expect(result.markdownText.contains("Hello"))
		#expect(result.markdownText.contains("World"))
	}

	@Test func stripsNavAndFormElements() {
		let html = "<nav><a href='/'>Home</a></nav><p>Content</p><form><input></form>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(!result.markdownText.contains("Home"))
		#expect(result.markdownText.contains("Content"))
	}

	@Test func stripsIframes() {
		let html = "<p>Before</p><iframe src='https://ads.example.com'></iframe><p>After</p>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(!result.markdownText.contains("iframe"))
		#expect(!result.markdownText.contains("ads.example.com"))
		#expect(result.markdownText.contains("Before"))
		#expect(result.markdownText.contains("After"))
	}

	@Test func convertsHeadings() {
		let html = "<h1>Title</h1><h2>Section</h2><h3>Subsection</h3>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.markdownText.contains("# Title"))
		#expect(result.markdownText.contains("## Section"))
		#expect(result.markdownText.contains("### Subsection"))
	}

	@Test func convertsParagraphs() {
		let html = "<p>First paragraph</p><p>Second paragraph</p>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.markdownText.contains("First paragraph"))
		#expect(result.markdownText.contains("Second paragraph"))
	}

	@Test func convertsListItems() {
		let html = "<ul><li>Item one</li><li>Item two</li></ul>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.markdownText.contains("- Item one"))
		#expect(result.markdownText.contains("- Item two"))
	}

	@Test func convertsBlockquotes() {
		let html = "<blockquote><p>A wise quote</p></blockquote>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.markdownText.contains("> "))
		#expect(result.markdownText.contains("A wise quote"))
	}

	@Test func extractsImgWithAlt() {
		let html = """
		<p>Text before</p>
		<img src="https://example.com/photo.jpg" alt="A sunset">
		<p>Text after</p>
		"""
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.imageReferences.count == 1)
		#expect(result.imageReferences[1]?.src == "https://example.com/photo.jpg")
		#expect(result.imageReferences[1]?.alt == "A sunset")
		#expect(result.markdownText.contains("[Image 1: A sunset]"))
		#expect(!result.markdownText.contains("<img"))
	}

	@Test func extractsFigureWithCaption() {
		let html = """
		<figure>
		  <img src="https://example.com/chart.png" alt="Revenue chart">
		  <figcaption>Figure 1: Q3 Revenue</figcaption>
		</figure>
		"""
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.imageReferences.count == 1)
		#expect(result.imageReferences[1]?.src == "https://example.com/chart.png")
		#expect(result.imageReferences[1]?.alt == "Revenue chart")
		#expect(result.imageReferences[1]?.caption == "Figure 1: Q3 Revenue")
		#expect(result.markdownText.contains("[Image 1: Revenue chart | Caption: Figure 1: Q3 Revenue]"))
	}

	@Test func extractsImgWithoutAlt() {
		let html = "<img src='https://example.com/decorative.png'>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.imageReferences.count == 1)
		#expect(result.imageReferences[1]?.src == "https://example.com/decorative.png")
		#expect(result.imageReferences[1]?.alt == nil)
		#expect(result.markdownText.contains("[Image 1]"))
	}

	@Test func numbersMultipleImages() {
		let html = """
		<img src="https://example.com/a.jpg" alt="First">
		<img src="https://example.com/b.jpg" alt="Second">
		<img src="https://example.com/c.jpg" alt="Third">
		"""
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.imageReferences.count == 3)
		#expect(result.markdownText.contains("[Image 1: First]"))
		#expect(result.markdownText.contains("[Image 2: Second]"))
		#expect(result.markdownText.contains("[Image 3: Third]"))
	}

	@Test func decodesHTMLEntities() {
		let html = "<p>Tom &amp; Jerry &mdash; a classic &lt;show&gt;</p>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.markdownText.contains("Tom & Jerry"))
		#expect(result.markdownText.contains("<show>"))
	}

	@Test func handlesEmptyInput() {
		let result = ArticlePreprocessor.preprocess("")
		#expect(result.markdownText == "")
		#expect(result.imageReferences.isEmpty)
	}

	@Test func handlesPlainTextInput() {
		let result = ArticlePreprocessor.preprocess("Just plain text, no HTML")
		#expect(result.markdownText.contains("Just plain text, no HTML"))
		#expect(result.imageReferences.isEmpty)
	}

	@Test func convertsLineBreaks() {
		let html = "<p>Line one<br>Line two<br/>Line three</p>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.markdownText.contains("Line one\nLine two\nLine three"))
	}

	@Test func decodesNumericEntities() {
		let html = "<p>&#169; 2026 &#x2014; All rights reserved</p>"
		let result = ArticlePreprocessor.preprocess(html)
		#expect(result.markdownText.contains("\u{00A9}"))
		#expect(result.markdownText.contains("\u{2014}"))
	}
}
