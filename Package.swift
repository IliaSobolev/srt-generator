// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SRTGenerator",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.0"),
    ],
    targets: [
        .executableTarget(
            name: "SRTGenerator",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/SRTGenerator",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
