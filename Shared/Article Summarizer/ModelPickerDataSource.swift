//
//  ModelPickerDataSource.swift
//  NetNewsWire
//

import Foundation
import OllamaKit

@MainActor
final class ModelPickerDataSource {

	struct ModelItem {
		let name: String
		let displayName: String
		let sizeDescription: String
		let isLocal: Bool
	}

	private(set) var items: [ModelItem] = []
	private(set) var isLoading = true
	private(set) var errorMessage: String?

	private let service: OllamaService

	init(service: OllamaService = OllamaService()) {
		self.service = service
	}

	func loadModels() async {
		isLoading = true
		errorMessage = nil

		do {
			let localModels = try await service.listModels()
			let localNames = Set(localModels.map { $0.name })

			var allItems: [ModelItem] = []

			for model in localModels {
				let sizeGB = String(format: "%.1f GB", Double(model.size) / 1_000_000_000)
				allItems.append(ModelItem(
					name: model.name,
					displayName: model.name,
					sizeDescription: sizeGB,
					isLocal: true
				))
			}

			for rec in OllamaSummarizer.recommendedModels where !localNames.contains(rec.name) {
				allItems.append(ModelItem(
					name: rec.name,
					displayName: "Download \(rec.displayName)",
					sizeDescription: rec.sizeDescription,
					isLocal: false
				))
			}

			items = allItems
		} catch {
			errorMessage = "Could not connect to Ollama. Is it running?"
			items = []
		}

		isLoading = false
	}

	func pullModel(_ name: String) async throws {
		try await service.pullModel(name) { _ in }
		await loadModels()
	}
}
