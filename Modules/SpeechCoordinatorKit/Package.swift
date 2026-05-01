// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "SpeechCoordinatorKit",
	platforms: [.macOS(.v15), .iOS(.v17)],
	products: [
		.library(
			name: "SpeechCoordinatorKit",
			type: .dynamic,
			targets: ["SpeechCoordinatorKit"])
	],
	dependencies: [
		.package(path: "../Articles"),
		.package(path: "../ArticleSpeech"),
		.package(path: "../AppleSpeechKit")
	],
	targets: [
		.target(
			name: "SpeechCoordinatorKit",
			dependencies: ["Articles", "ArticleSpeech", "AppleSpeechKit"],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.testTarget(
			name: "SpeechCoordinatorKitTests",
			dependencies: ["SpeechCoordinatorKit", "Articles", "ArticleSpeech"]
		)
	]
)
