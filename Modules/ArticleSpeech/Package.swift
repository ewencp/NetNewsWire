// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "ArticleSpeech",
	platforms: [.macOS(.v15), .iOS(.v17)],
	products: [
		.library(
			name: "ArticleSpeech",
			type: .dynamic,
			targets: ["ArticleSpeech"])
	],
	targets: [
		.target(
			name: "ArticleSpeech",
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.testTarget(
			name: "ArticleSpeechTests",
			dependencies: ["ArticleSpeech"]
		)
	]
)
