import Foundation

/// Stateless HTTP client for the Ollama API.
public struct OllamaService: Sendable {

	public let baseURL: URL

	public init(baseURL: URL = URL(string: "http://localhost:11434")!) {
		self.baseURL = baseURL
	}

	// MARK: - Health Check

	/// Returns true if Ollama is reachable at the configured endpoint.
	public func isAvailable() async -> Bool {
		do {
			_ = try await listModels()
			return true
		} catch {
			return false
		}
	}

	// MARK: - List Models

	/// Lists locally available models.
	public func listModels() async throws -> [OllamaModel] {
		let url = baseURL.appendingPathComponent("api/tags")
		let (data, response) = try await makeRequest(url: url)
		try validateResponse(response, data: data)

		do {
			let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
			return tagsResponse.models
		} catch {
			throw OllamaError.decodingFailed(error)
		}
	}

	// MARK: - Generate

	/// Generates a completion using the specified model.
	public func generate(model: String, prompt: String) async throws -> String {
		let url = baseURL.appendingPathComponent("api/generate")
		let requestBody = OllamaGenerateRequest(model: model, prompt: prompt, stream: false)
		let bodyData = try JSONEncoder().encode(requestBody)

		let (data, response) = try await makeRequest(url: url, method: "POST", body: bodyData)
		try validateResponse(response, data: data)

		do {
			let generateResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
			return generateResponse.response
		} catch {
			throw OllamaError.decodingFailed(error)
		}
	}

	// MARK: - Pull Model

	/// Pulls (downloads) a model, reporting progress via callback.
	public func pullModel(_ name: String, progress: @escaping @Sendable (Double) -> Void) async throws {
		let url = baseURL.appendingPathComponent("api/pull")
		let requestBody = OllamaPullRequest(name: name)
		let bodyData = try JSONEncoder().encode(requestBody)

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = bodyData

		let (bytes, response) = try await URLSession.shared.bytes(for: request)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw OllamaError.notRunning
		}
		guard httpResponse.statusCode == 200 else {
			throw OllamaError.requestFailed(
				statusCode: httpResponse.statusCode,
				message: "Pull request failed"
			)
		}

		for try await line in bytes.lines {
			guard let lineData = line.data(using: .utf8),
				  let pullProgress = try? JSONDecoder().decode(OllamaPullProgress.self, from: lineData) else {
				continue
			}
			if let total = pullProgress.total, total > 0,
			   let completed = pullProgress.completed {
				progress(Double(completed) / Double(total))
			}
		}
	}

	// MARK: - Private

	private func makeRequest(url: URL, method: String = "GET", body: Data? = nil) async throws -> (Data, URLResponse) {
		var request = URLRequest(url: url)
		request.httpMethod = method
		if let body {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = body
		}
		// Ollama generation can be slow — no aggressive timeout
		request.timeoutInterval = 300

		do {
			return try await URLSession.shared.data(for: request)
		} catch let error as URLError where error.code == .cannotConnectToHost || error.code == .timedOut {
			throw OllamaError.notRunning
		}
	}

	private func validateResponse(_ response: URLResponse, data: Data) throws {
		guard let httpResponse = response as? HTTPURLResponse else {
			throw OllamaError.notRunning
		}
		guard (200...299).contains(httpResponse.statusCode) else {
			let message = String(data: data, encoding: .utf8) ?? "Unknown error"
			throw OllamaError.requestFailed(statusCode: httpResponse.statusCode, message: message)
		}
	}
}
