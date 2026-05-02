// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "ArticleAI",
	platforms: [.macOS(.v15), .iOS(.v17)],
	products: [
		.library(
			name: "ArticleAI",
			type: .dynamic,
			targets: ["ArticleAI"])
	],
	dependencies: [
		.package(url: "https://github.com/brentsimmons/Tidemark", from: "1.0.0")
	],
	targets: [
		.target(
			name: "ArticleAI",
			dependencies: ["Tidemark"],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.testTarget(
			name: "ArticleAITests",
			dependencies: ["ArticleAI"]
		)
	]
)
