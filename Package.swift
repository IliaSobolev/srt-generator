// swift-tools-version: 6.2
import PackageDescription

/// Warnings fail the build for our own targets ("no new warnings" is part of the definition of done).
let settings: [SwiftSetting] = [.swiftLanguageMode(.v5), .treatAllWarnings(as: .error)]

let package = Package(
    name: "SRTGenerator",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SRTCore", targets: ["SRTCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.0"),
    ],
    targets: [
        // Pure app logic. Depends only on Apple system frameworks; every service is behind a protocol.
        .target(name: "SRTCore", path: "Sources/SRTCore", swiftSettings: settings),
        // Adapters that plug the real speech engines into SRTCore's protocols.
        .target(
            name: "SRTEngines",
            dependencies: [
                "SRTCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/SRTEngines",
            swiftSettings: settings
        ),
        // SwiftUI app + CLI; also the composition root that wires live dependencies.
        .executableTarget(
            name: "SRTGenerator",
            dependencies: ["SRTCore", "SRTEngines"],
            path: "Sources/SRTGenerator",
            swiftSettings: settings
        ),
        .testTarget(
            name: "SRTCoreTests",
            dependencies: ["SRTCore"],
            path: "Tests/SRTCoreTests",
            swiftSettings: settings
        ),
    ]
)
