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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MeetingTranscriber",
            dependencies: []
        ),
        .testTarget(
            name: "MeetingTranscriberTests",
            dependencies: ["MeetingTranscriber"]
        )
    ]
)

