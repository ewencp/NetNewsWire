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
		.package(path: "../RSMarkdown")
	],
	targets: [
		.target(
			name: "ArticleAI",
			dependencies: ["RSMarkdown"],
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
