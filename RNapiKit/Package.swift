// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RNapiKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "RNapiUI", targets: ["RNapiUI"]),
        .library(name: "DownloadPipeline", targets: ["DownloadPipeline"]),
        .executable(name: "rnapi-cli", targets: ["rnapi-cli"]),
    ],
    dependencies: [
        // Vendored: PLzmaSDK uses unsafe build flags, which SwiftPM only
        // permits for local path dependencies.
        .package(path: "../Vendor/PLzmaSDK"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "RNapiCore"
        ),
        .target(
            name: "SubtitleFormats",
            dependencies: ["RNapiCore"]
        ),
        .target(
            name: "MediaInfo",
            dependencies: ["RNapiCore"]
        ),
        .target(
            name: "SevenZip",
            dependencies: [
                .product(name: "PLzmaSDK", package: "PLzmaSDK")
            ]
        ),
        .target(
            name: "Engines",
            dependencies: ["RNapiCore", "SevenZip"]
        ),
        .target(
            name: "DownloadPipeline",
            dependencies: ["RNapiCore", "SubtitleFormats", "MediaInfo", "Engines"]
        ),
        .target(
            name: "RNapiSettings",
            dependencies: ["RNapiCore"]
        ),
        .target(
            name: "RNapiUI",
            dependencies: ["DownloadPipeline", "RNapiSettings"]
        ),
        .executableTarget(
            name: "rnapi-cli",
            dependencies: [
                "DownloadPipeline",
                "RNapiSettings",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "RNapiCoreTests",
            dependencies: ["RNapiCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SubtitleFormatsTests",
            dependencies: ["SubtitleFormats"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SevenZipTests",
            dependencies: ["SevenZip"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "EnginesTests",
            dependencies: ["Engines"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DownloadPipelineTests",
            dependencies: ["DownloadPipeline"]
        ),
    ]
)
