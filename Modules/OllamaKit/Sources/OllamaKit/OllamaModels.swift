import Foundation

/// Ollama API error.
public enum OllamaError: Error, Sendable {

	case notRunning
	case requestFailed(statusCode: Int, message: String)
	case decodingFailed(Error)
}

// MARK: - /api/tags (list models)

public struct OllamaModel: Codable, Sendable {

	public let name: String
	public let size: Int64
	public let details: OllamaModelDetails?
}

public struct OllamaModelDetails: Codable, Sendable {

	public let parameterSize: String?
	public let quantizationLevel: String?

	enum CodingKeys: String, CodingKey {
		case parameterSize = "parameter_size"
		case quantizationLevel = "quantization_level"
	}
}

struct OllamaTagsResponse: Codable {

	let models: [OllamaModel]
}

// MARK: - /api/generate

struct OllamaGenerateRequest: Codable {

	let model: String
	let prompt: String
	let stream: Bool
}

struct OllamaGenerateResponse: Codable {

	let response: String
	let done: Bool
}

// MARK: - /api/pull

struct OllamaPullRequest: Codable {

	let name: String
}

struct OllamaPullProgress: Codable {

	let status: String
	let total: Int64?
	let completed: Int64?
}
