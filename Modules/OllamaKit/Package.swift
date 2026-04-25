// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "OllamaKit",
	platforms: [.macOS(.v15), .iOS(.v17)],
	products: [
		.library(
			name: "OllamaKit",
			type: .dynamic,
			targets: ["OllamaKit"])
	],
	dependencies: [
		.package(path: "../ArticleAI")
	],
	targets: [
		.target(
			name: "OllamaKit",
			dependencies: ["ArticleAI"],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.testTarget(
			name: "OllamaKitTests",
			dependencies: ["OllamaKit"]
		)
	]
)
