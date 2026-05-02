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
	dependencies: [
		.package(name: "RSParser", path: "../RSParser")
	],
	targets: [
		.target(
			name: "ArticleSpeech",
			dependencies: [
				.product(name: "RSParser", package: "RSParser")
			],
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
