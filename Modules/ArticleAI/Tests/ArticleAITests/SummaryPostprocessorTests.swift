import Testing
@testable import ArticleAI

struct SummaryPostprocessorTests {

	@Test func rehydratesNumberedImageReference() {
		let markdown = "This article shows [Image 1] with some analysis."
		let refs: [Int: ImageReference] = [
			1: ImageReference(src: "https://example.com/chart.png", alt: "Revenue chart")
		]
		let html = SummaryPostprocessor.postprocess(markdown: markdown, imageReferences: refs)
		#expect(html.contains("<img src=\"https://example.com/chart.png\" alt=\"Revenue chart\""))
		#expect(!html.contains("[Image 1]"))
	}

	@Test func rehydratesImageReferenceWithTrailingText() {
		let markdown = "See [Image 2: some description] for details."
		let refs: [Int: ImageReference] = [
			2: ImageReference(src: "https://example.com/photo.jpg", alt: "Photo")
		]
		let html = SummaryPostprocessor.postprocess(markdown: markdown, imageReferences: refs)
		#expect(html.contains("<img src=\"https://example.com/photo.jpg\" alt=\"Photo\""))
		#expect(!html.contains("[Image 2"))
	}

	@Test func rehydratesMultipleImages() {
		let markdown = "[Image 1] and [Image 3] are important."
		let refs: [Int: ImageReference] = [
			1: ImageReference(src: "https://example.com/a.png", alt: "Alpha"),
			2: ImageReference(src: "https://example.com/b.png", alt: "Beta"),
			3: ImageReference(src: "https://example.com/c.png", alt: "Gamma")
		]
		let html = SummaryPostprocessor.postprocess(markdown: markdown, imageReferences: refs)
		#expect(html.contains("src=\"https://example.com/a.png\""))
		#expect(html.contains("src=\"https://example.com/c.png\""))
		#expect(!html.contains("src=\"https://example.com/b.png\""))
	}

	@Test func leavesUnmatchedReferencesAsText() {
		let markdown = "See [Image 5] for details."
		let refs: [Int: ImageReference] = [
			1: ImageReference(src: "https://example.com/a.png")
		]
		let html = SummaryPostprocessor.postprocess(markdown: markdown, imageReferences: refs)
		#expect(!html.contains("<img"))
	}

	@Test func convertsMarkdownToHTML() {
		let markdown = "## Summary\n\nThis is the **key** point."
		let html = SummaryPostprocessor.postprocess(markdown: markdown, imageReferences: [:])
		#expect(html.contains("<h2>"))
		#expect(html.contains("Summary"))
		#expect(html.contains("<strong>key</strong>"))
	}

	@Test func handlesEmptyMarkdown() {
		let html = SummaryPostprocessor.postprocess(markdown: "", imageReferences: [:])
		#expect(html.isEmpty)
	}

	@Test func includesCaptionInFigure() {
		let markdown = "The chart [Image 1] shows growth."
		let refs: [Int: ImageReference] = [
			1: ImageReference(src: "https://example.com/chart.png", alt: "Growth chart", caption: "Figure 1: Annual growth")
		]
		let html = SummaryPostprocessor.postprocess(markdown: markdown, imageReferences: refs)
		#expect(html.contains("<figure"))
		#expect(html.contains("<figcaption>Figure 1: Annual growth</figcaption>"))
	}

	@Test func imageWithoutAltOmitsAltAttribute() {
		let markdown = "[Image 1]"
		let refs: [Int: ImageReference] = [
			1: ImageReference(src: "https://example.com/img.png", alt: nil)
		]
		let html = SummaryPostprocessor.postprocess(markdown: markdown, imageReferences: refs)
		#expect(html.contains("<img src=\"https://example.com/img.png\""))
		#expect(!html.contains("alt="))
	}
}
