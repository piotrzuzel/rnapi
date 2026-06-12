// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QNapiKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "QNapiUI", targets: ["QNapiUI"]),
        .library(name: "DownloadPipeline", targets: ["DownloadPipeline"]),
        .executable(name: "qnapi-cli", targets: ["qnapi-cli"]),
    ],
    dependencies: [
        // Vendored: PLzmaSDK uses unsafe build flags, which SwiftPM only
        // permits for local path dependencies.
        .package(path: "../Vendor/PLzmaSDK"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "QNapiCore"
        ),
        .target(
            name: "SubtitleFormats",
            dependencies: ["QNapiCore"]
        ),
        .target(
            name: "MediaInfo",
            dependencies: ["QNapiCore"]
        ),
        .target(
            name: "SevenZip",
            dependencies: [
                .product(name: "PLzmaSDK", package: "PLzmaSDK")
            ]
        ),
        .target(
            name: "Engines",
            dependencies: ["QNapiCore", "SevenZip"]
        ),
        .target(
            name: "DownloadPipeline",
            dependencies: ["QNapiCore", "SubtitleFormats", "MediaInfo", "Engines"]
        ),
        .target(
            name: "QNapiSettings",
            dependencies: ["QNapiCore"]
        ),
        .target(
            name: "QNapiUI",
            dependencies: ["DownloadPipeline", "QNapiSettings"]
        ),
        .executableTarget(
            name: "qnapi-cli",
            dependencies: [
                "DownloadPipeline",
                "QNapiSettings",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "QNapiCoreTests",
            dependencies: ["QNapiCore"],
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
