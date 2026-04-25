import Foundation

/// Result of article summarization, containing rendered HTML.
public struct SummarizedArticle: Equatable, Sendable {

	public let contentHTML: String

	public init(contentHTML: String) {
		self.contentHTML = contentHTML
	}
}

/// Errors that can occur during summarization.
public enum SummarizationError: Error, Sendable {

	/// The summarization backend is not reachable.
	case serviceUnavailable

	/// The configured model is not available.
	case modelNotFound(String)

	/// The model returned an error during generation.
	case generationFailed(String)
}

/// Protocol for article summarization backends.
///
/// Accepts raw article HTML and returns a `SummarizedArticle` with
/// rendered HTML ready for display. Implementations handle preprocessing
/// (HTML cleanup, image reference extraction) and postprocessing
/// (markdown to HTML, image rehydration) internally.
public protocol Summarizer: Sendable {

	func summarize(_ articleHTML: String, sentenceCount: Int) async throws -> SummarizedArticle

	var isAvailable: Bool { get async }
}
