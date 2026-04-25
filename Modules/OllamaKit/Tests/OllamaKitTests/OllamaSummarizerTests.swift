import Testing
import Foundation
@testable import OllamaKit
import ArticleAI

struct OllamaSummarizerTests {

	@Test func buildPromptWithLowSentenceCount() {
		let prompt = OllamaSummarizer.buildPrompt(
			preprocessedText: "Some article text here.",
			sentenceCount: 3
		)
		#expect(prompt.contains("3 sentences"))
		#expect(prompt.contains("Some article text here."))
		#expect(prompt.contains("ONLY the condensed text"))
	}

	@Test func buildPromptWithHighSentenceCountUsesParagraphs() {
		let prompt = OllamaSummarizer.buildPrompt(
			preprocessedText: "Article text.",
			sentenceCount: 8
		)
		#expect(prompt.contains("paragraph"))
		#expect(!prompt.contains("8 sentences"))
	}

	@Test func buildPromptWith12SentencesUses3To4Paragraphs() {
		let prompt = OllamaSummarizer.buildPrompt(
			preprocessedText: "Text.",
			sentenceCount: 12
		)
		#expect(prompt.contains("3-4 paragraphs"))
	}

	@Test func buildPromptWithOneSentence() {
		let prompt = OllamaSummarizer.buildPrompt(
			preprocessedText: "Text.",
			sentenceCount: 1
		)
		#expect(prompt.contains("1 sentence"))
	}

	@Test func lengthInstructionForVariousCounts() {
		#expect(OllamaSummarizer.lengthInstruction(for: 1) == "1 sentence")
		#expect(OllamaSummarizer.lengthInstruction(for: 2) == "2 sentences")
		#expect(OllamaSummarizer.lengthInstruction(for: 4) == "4 sentences")
		#expect(OllamaSummarizer.lengthInstruction(for: 5) == "1-2 short paragraphs")
		#expect(OllamaSummarizer.lengthInstruction(for: 8) == "2-3 paragraphs")
		#expect(OllamaSummarizer.lengthInstruction(for: 12) == "3-4 paragraphs")
	}

	@Test func buildPromptIncludesImageInstructionsWhenImagesPresent() {
		let prompt = OllamaSummarizer.buildPrompt(
			preprocessedText: "Article with [Image 1: photo].",
			sentenceCount: 3,
			imageCount: 1
		)
		#expect(prompt.contains("lead or hero image"))
		#expect(prompt.contains("Do not invent"))
	}

	@Test func buildPromptOmitsImageInstructionsWhenNoImages() {
		let prompt = OllamaSummarizer.buildPrompt(
			preprocessedText: "Article without images.",
			sentenceCount: 3,
			imageCount: 0
		)
		#expect(!prompt.contains("lead or hero image"))
		#expect(!prompt.contains("[Image"))
	}

	@Test func defaultModelName() {
		let summarizer = OllamaSummarizer()
		#expect(summarizer.modelName == "llama3.2:latest")
	}

	@Test func recommendedModelsNotEmpty() {
		#expect(!OllamaSummarizer.recommendedModels.isEmpty)
		#expect(OllamaSummarizer.recommendedModels.allSatisfy { !$0.name.isEmpty })
	}
}
