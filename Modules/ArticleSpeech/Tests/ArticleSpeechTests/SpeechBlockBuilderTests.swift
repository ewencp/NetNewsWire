import Testing
import Foundation
@testable import ArticleSpeech

struct SpeechBlockBuilderTests {

	private func makeContent(_ segments: [SpeechContent.Segment]) -> SpeechContent {
		SpeechContent(segments: segments, title: nil, language: nil, sourceArticleID: "a1")
	}

	@Test func paragraphProducesParagraphBlock() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.paragraph("Hi.")]))
		#expect(blocks == [SpeechBlock(text: "Hi.", kind: .paragraph)])
	}

	@Test func headingPreservesLevelInBlockKind() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.heading(level: 2, "Topic")]))
		#expect(blocks == [SpeechBlock(text: "Section 1: Topic.", kind: .heading(level: 2))])
	}

	@Test func headingAlreadyEndingWithPeriodIsNotDoubled() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.heading(level: 1, "End.")]))
		#expect(blocks == [SpeechBlock(text: "Section 1: End.", kind: .heading(level: 1))])
	}

	@Test func headingsAtMultipleLevelsCarryNestedSectionNumber() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([
			.heading(level: 2, "First Top"),
			.heading(level: 3, "First Sub"),
			.heading(level: 2, "Second Top"),
			.heading(level: 3, "Second Sub A"),
			.heading(level: 3, "Second Sub B"),
		]))
		#expect(blocks == [
			SpeechBlock(text: "Section 1: First Top.", kind: .heading(level: 2)),
			SpeechBlock(text: "Section 1.1: First Sub.", kind: .heading(level: 3)),
			SpeechBlock(text: "Section 2: Second Top.", kind: .heading(level: 2)),
			SpeechBlock(text: "Section 2.1: Second Sub A.", kind: .heading(level: 3)),
			SpeechBlock(text: "Section 2.2: Second Sub B.", kind: .heading(level: 3)),
		])
	}

	@Test func skippedHeadingLevelsFilterZeros() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([
			.heading(level: 2, "Top"),
			.heading(level: 4, "Deep"),
		]))
		#expect(blocks == [
			SpeechBlock(text: "Section 1: Top.", kind: .heading(level: 2)),
			SpeechBlock(text: "Section 1.1: Deep.", kind: .heading(level: 4)),
		])
	}

	@Test func headingAtH7OrHigherIsNotNumbered() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([
			.heading(level: 7, "Out of range"),
			.heading(level: 0, "Also out"),
		]))
		#expect(blocks == [
			SpeechBlock(text: "Out of range.", kind: .heading(level: 7)),
			SpeechBlock(text: "Also out.", kind: .heading(level: 0)),
		])
	}

	@Test func blockQuoteIsPrefixedWithQuote() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.blockQuote("Be brief.")]))
		#expect(blocks == [SpeechBlock(text: "Quote: Be brief.", kind: .blockQuote)])
	}

	@Test func unorderedListItemUsesPlainText() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([
			.listItem(depth: 0, ordering: .unordered, "First")
		]))
		#expect(blocks == [SpeechBlock(text: "First", kind: .listItem(depth: 0, ordering: .unordered))])
	}

	@Test func orderedListItemsHaveNumericPrefix() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([
			.listItem(depth: 0, ordering: .ordered(index: 1), "First"),
			.listItem(depth: 0, ordering: .ordered(index: 2), "Second"),
			.listItem(depth: 0, ordering: .ordered(index: 3), "Third"),
		]))
		#expect(blocks == [
			SpeechBlock(text: "1. First", kind: .listItem(depth: 0, ordering: .ordered(index: 1))),
			SpeechBlock(text: "2. Second", kind: .listItem(depth: 0, ordering: .ordered(index: 2))),
			SpeechBlock(text: "3. Third", kind: .listItem(depth: 0, ordering: .ordered(index: 3))),
		])
	}

	@Test func mixedOrderedAndUnorderedListItems() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([
			.listItem(depth: 0, ordering: .ordered(index: 1), "Step 1"),
			.listItem(depth: 0, ordering: .unordered, "Note"),
			.listItem(depth: 0, ordering: .ordered(index: 2), "Step 2"),
		]))
		#expect(blocks == [
			SpeechBlock(text: "1. Step 1", kind: .listItem(depth: 0, ordering: .ordered(index: 1))),
			SpeechBlock(text: "Note", kind: .listItem(depth: 0, ordering: .unordered)),
			SpeechBlock(text: "2. Step 2", kind: .listItem(depth: 0, ordering: .ordered(index: 2))),
		])
	}

	@Test func nestedOrderedListItemsUseOwnIndex() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([
			.listItem(depth: 0, ordering: .ordered(index: 1), "Outer 1"),
			.listItem(depth: 1, ordering: .ordered(index: 1), "Inner A"),
			.listItem(depth: 1, ordering: .ordered(index: 2), "Inner B"),
			.listItem(depth: 0, ordering: .ordered(index: 2), "Outer 2"),
		]))
		#expect(blocks == [
			SpeechBlock(text: "1. Outer 1", kind: .listItem(depth: 0, ordering: .ordered(index: 1))),
			SpeechBlock(text: "1. Inner A", kind: .listItem(depth: 1, ordering: .ordered(index: 1))),
			SpeechBlock(text: "2. Inner B", kind: .listItem(depth: 1, ordering: .ordered(index: 2))),
			SpeechBlock(text: "2. Outer 2", kind: .listItem(depth: 0, ordering: .ordered(index: 2))),
		])
	}

	@Test func imageWithAltUsesAltText() async {
		let descriptor = SpeechContent.ImageDescriptor(src: "x", alt: "A cat", caption: nil)
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.image(descriptor)]))
		#expect(blocks == [SpeechBlock(text: "Image: A cat.", kind: .imageDescription)])
	}

	@Test func imageWithoutAltOrCaptionFallsBackToBareWord() async {
		let descriptor = SpeechContent.ImageDescriptor(src: "x", alt: nil, caption: nil)
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.image(descriptor)]))
		#expect(blocks == [SpeechBlock(text: "Image.", kind: .imageDescription)])
	}

	@Test func figureWithCaptionPrefersCaptionOverAlt() async {
		let descriptor = SpeechContent.ImageDescriptor(src: "x", alt: "A cat", caption: "Felix in the sun")
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.figure(descriptor)]))
		#expect(blocks == [SpeechBlock(text: "Figure: Felix in the sun.", kind: .figureDescription)])
	}

	@Test func figureWithOnlyAltUsesAltText() async {
		let descriptor = SpeechContent.ImageDescriptor(src: "x", alt: "Diagram", caption: nil)
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.figure(descriptor)]))
		#expect(blocks == [SpeechBlock(text: "Figure: Diagram.", kind: .figureDescription)])
	}

	@Test func codeBlockWithLanguageNamesIt() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([
			.codeBlock(language: "swift", content: "let x = 1")
		]))
		#expect(blocks == [SpeechBlock(text: "Code block in swift omitted.", kind: .codeNotice)])
	}

	@Test func codeBlockWithoutLanguageDropsLanguageMention() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([
			.codeBlock(language: nil, content: "x")
		]))
		#expect(blocks == [SpeechBlock(text: "Code block omitted.", kind: .codeNotice)])
	}

	@Test func tableWithCountsMentionsBothDimensions() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.table(rowCount: 3, columnCount: 5)]))
		#expect(blocks == [SpeechBlock(text: "See the 3-by-5 table in the article.", kind: .tableNotice)])
	}

	@Test func tableWithoutCountsUsesGenericText() async {
		let blocks = await SpeechBlockBuilder.makeBlocks(from: makeContent([.table(rowCount: nil, columnCount: nil)]))
		#expect(blocks == [SpeechBlock(text: "See table in the article.", kind: .tableNotice)])
	}

	@Test func customImageRendererIsUsed() async {
		let descriptor = SpeechContent.ImageDescriptor(src: "x", alt: "A cat", caption: nil)
		let custom = SpeechBlockBuilder.ImageRenderer { d in
			"CUSTOM: \(d.alt ?? "?")"
		}
		let blocks = await SpeechBlockBuilder.makeBlocks(
			from: makeContent([.image(descriptor)]),
			imageRenderer: custom
		)
		#expect(blocks == [SpeechBlock(text: "CUSTOM: A cat", kind: .imageDescription)])
	}
}
