// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingTranscriber",
    platforms: [
        .macOS(.v14)  // Required for FluidAudio
    ],
    products: [
        .executable(
            name: "MeetingTranscriber",
            targets: ["MeetingTranscriber"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "MeetingTranscriber",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        .testTarget(
            name: "MeetingTranscriberTests",
            dependencies: ["MeetingTranscriber"]
        )
    ]
)

