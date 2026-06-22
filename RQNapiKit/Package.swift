// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RQNapiKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "RQNapiUI", targets: ["RQNapiUI"]),
        .library(name: "DownloadPipeline", targets: ["DownloadPipeline"]),
        .executable(name: "rqnapi-cli", targets: ["rqnapi-cli"]),
    ],
    dependencies: [
        // Vendored: PLzmaSDK uses unsafe build flags, which SwiftPM only
        // permits for local path dependencies.
        .package(path: "../Vendor/PLzmaSDK"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "RQNapiCore"
        ),
        .target(
            name: "SubtitleFormats",
            dependencies: ["RQNapiCore"]
        ),
        .target(
            name: "MediaInfo",
            dependencies: ["RQNapiCore"]
        ),
        .target(
            name: "SevenZip",
            dependencies: [
                .product(name: "PLzmaSDK", package: "PLzmaSDK")
            ]
        ),
        .target(
            name: "Engines",
            dependencies: ["RQNapiCore", "SevenZip"]
        ),
        .target(
            name: "DownloadPipeline",
            dependencies: ["RQNapiCore", "SubtitleFormats", "MediaInfo", "Engines"]
        ),
        .target(
            name: "RQNapiSettings",
            dependencies: ["RQNapiCore"]
        ),
        .target(
            name: "RQNapiUI",
            dependencies: ["DownloadPipeline", "RQNapiSettings"]
        ),
        .executableTarget(
            name: "rqnapi-cli",
            dependencies: [
                "DownloadPipeline",
                "RQNapiSettings",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "RQNapiCoreTests",
            dependencies: ["RQNapiCore"],
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
