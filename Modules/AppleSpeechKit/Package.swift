// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "AppleSpeechKit",
	platforms: [.macOS(.v15), .iOS(.v17)],
	products: [
		.library(
			name: "AppleSpeechKit",
			type: .dynamic,
			targets: ["AppleSpeechKit"])
	],
	dependencies: [
		.package(path: "../ArticleSpeech")
	],
	targets: [
		.target(
			name: "AppleSpeechKit",
			dependencies: ["ArticleSpeech"],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.testTarget(
			name: "AppleSpeechKitTests",
			dependencies: ["AppleSpeechKit", "ArticleSpeech"]
		)
	]
)
