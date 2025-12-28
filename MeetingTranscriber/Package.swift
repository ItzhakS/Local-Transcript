// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingTranscriber",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MeetingTranscriber",
            targets: ["MeetingTranscriber"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "MeetingTranscriber",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        ),
        .testTarget(
            name: "MeetingTranscriberTests",
            dependencies: ["MeetingTranscriber"]
        )
    ]
)

