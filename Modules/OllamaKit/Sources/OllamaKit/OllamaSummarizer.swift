import Foundation
import ArticleAI

/// Recommended models for summarization, shown as download options in the model picker.
public struct RecommendedModel: Sendable {

	public let name: String
	public let displayName: String
	public let sizeDescription: String

	public init(name: String, displayName: String, sizeDescription: String) {
		self.name = name
		self.displayName = displayName
		self.sizeDescription = sizeDescription
	}
}

/// Ollama-based article summarizer.
///
/// Orchestrates the full pipeline: preprocesses HTML input, builds the prompt,
/// calls OllamaService for generation, and postprocesses the LLM response
/// (image rehydration, markdown-to-HTML conversion).
public final class OllamaSummarizer: Summarizer {

	private let service: OllamaService
	public let modelName: String

	/// Models recommended for summarization, offered as download options.
	public static let recommendedModels: [RecommendedModel] = [
		RecommendedModel(name: "llama3.2:latest", displayName: "Llama 3.2", sizeDescription: "2.0 GB"),
		RecommendedModel(name: "qwen2.5:latest", displayName: "Qwen 2.5", sizeDescription: "1.5 GB"),
		RecommendedModel(name: "phi3:latest", displayName: "Phi-3", sizeDescription: "2.2 GB"),
	]

	public init(service: OllamaService = OllamaService(), modelName: String = "llama3.2:latest") {
		self.service = service
		self.modelName = modelName
	}

	// MARK: - Summarizer Protocol

	public var isAvailable: Bool {
		get async {
			await service.isAvailable()
		}
	}

	public func summarize(_ articleHTML: String, sentenceCount: Int) async throws -> SummarizedArticle {
		guard await service.isAvailable() else {
			throw SummarizationError.serviceUnavailable
		}

		// 1. Preprocess HTML to markdown text with image references
		let preprocessed = ArticlePreprocessor.preprocess(articleHTML)

		// 2. Build the prompt
		let prompt = Self.buildPrompt(
			preprocessedText: preprocessed.markdownText,
			sentenceCount: sentenceCount,
			imageCount: preprocessed.imageReferences.count
		)

		// 3. Call Ollama
		let response: String
		do {
			response = try await service.generate(model: modelName, prompt: prompt)
		} catch let error as OllamaError {
			switch error {
			case .requestFailed(let statusCode, let message):
				if message.contains("model") && message.contains("not found") {
					throw SummarizationError.modelNotFound(modelName)
				}
				throw SummarizationError.generationFailed("HTTP \(statusCode): \(message)")
			case .notRunning:
				throw SummarizationError.serviceUnavailable
			case .decodingFailed(let underlying):
				throw SummarizationError.generationFailed("Failed to decode response: \(underlying)")
			}
		}

		// 4. Postprocess: rehydrate images and convert markdown to HTML
		let contentHTML = SummaryPostprocessor.postprocess(
			markdown: response,
			imageReferences: preprocessed.imageReferences
		)

		return SummarizedArticle(contentHTML: contentHTML)
	}

	// MARK: - Prompt Construction (internal for testing)

	static func buildPrompt(preprocessedText: String, sentenceCount: Int, imageCount: Int = 0) -> String {
		let lengthDesc = lengthInstruction(for: sentenceCount)

		var instructions = """
		Condense the following article to approximately \(lengthDesc). \
		Preserve the original author's voice, perspective, and tone — write as \
		if the author wrote a shorter version, not as a third-party summary. \
		Do not refer to "the article" or "the author". \
		Output ONLY the condensed text in markdown format. Do not include any preamble, \
		commentary, or meta-text such as "Here is a summary" or notes about what \
		you could not do. Do not add a top-level title — the article title is \
		already displayed separately. IMPORTANT: Do NOT use markdown headings (#, ##, ###). \
		Write as plain prose paragraphs only.
		"""

		if imageCount > 0 {
			instructions += """

			The article contains \(imageCount) image(s) marked as [Image 1], [Image 2], etc. \
			If an image is a lead or hero image, include it in your summary. \
			If other images are important to understanding the content, include them \
			by writing their exact reference (e.g. [Image 1]) in your summary. \
			Do not invent or hallucinate image references that do not appear in the article. \
			Bracketed numbers like [1] or [2] that are NOT preceded by "Image" are footnotes, not images.
			"""
		}

		return """
		\(instructions)

		---

		\(preprocessedText)
		"""
	}

	/// Converts a sentence count to a natural language length instruction.
	public static func lengthInstruction(for sentenceCount: Int) -> String {
		switch sentenceCount {
		case 1:
			return "1 sentence"
		case 2...4:
			return "\(sentenceCount) sentences"
		case 5...7:
			return "1-2 short paragraphs"
		case 8...11:
			return "2-3 paragraphs"
		case 12...16:
			return "3-4 paragraphs"
		default:
			let paragraphs = (sentenceCount + 2) / 4
			return "\(paragraphs - 1)-\(paragraphs) paragraphs"
		}
	}
}
