// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "AudioPlayerKit",
	platforms: [.macOS(.v15), .iOS(.v17)],
	products: [
		.library(
			name: "AudioPlayerKit",
			type: .dynamic,
			targets: ["AudioPlayerKit"])
	],
	dependencies: [],
	targets: [
		.target(
			name: "AudioPlayerKit",
			dependencies: [],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		),
		.testTarget(
			name: "AudioPlayerKitTests",
			dependencies: ["AudioPlayerKit"]
		)
	]
)
