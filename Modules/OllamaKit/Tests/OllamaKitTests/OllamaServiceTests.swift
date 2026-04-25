import Testing
import Foundation
@testable import OllamaKit

struct OllamaServiceTests {

	@Test func tagsResponseDecodes() throws {
		let json = """
		{"models":[{"name":"llama3.2:latest","size":2000000000,"details":{"parameter_size":"3B","quantization_level":"Q4_0"}}]}
		"""
		let data = json.data(using: .utf8)!
		let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
		#expect(decoded.models.count == 1)
		#expect(decoded.models[0].name == "llama3.2:latest")
		#expect(decoded.models[0].size == 2_000_000_000)
		#expect(decoded.models[0].details?.parameterSize == "3B")
		#expect(decoded.models[0].details?.quantizationLevel == "Q4_0")
	}

	@Test func generateRequestEncodesCorrectly() throws {
		let request = OllamaGenerateRequest(model: "llama3.2", prompt: "Summarize this", stream: false)
		let data = try JSONEncoder().encode(request)
		let decoded = try JSONDecoder().decode(OllamaGenerateRequest.self, from: data)
		#expect(decoded.model == "llama3.2")
		#expect(decoded.prompt == "Summarize this")
		#expect(decoded.stream == false)
	}

	@Test func generateResponseDecodes() throws {
		let json = """
		{"response":"This is a summary.","done":true}
		"""
		let data = json.data(using: .utf8)!
		let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
		#expect(decoded.response == "This is a summary.")
		#expect(decoded.done == true)
	}

	@Test func pullProgressDecodes() throws {
		let json = """
		{"status":"downloading","total":4000000000,"completed":2000000000}
		"""
		let data = json.data(using: .utf8)!
		let decoded = try JSONDecoder().decode(OllamaPullProgress.self, from: data)
		#expect(decoded.status == "downloading")
		#expect(decoded.total == 4_000_000_000)
		#expect(decoded.completed == 2_000_000_000)
	}

	@Test func isAvailableReturnsFalseForBadHost() async {
		let service = OllamaService(baseURL: URL(string: "http://localhost:19999")!)
		let available = await service.isAvailable()
		#expect(available == false)
	}
}
