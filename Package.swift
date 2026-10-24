// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioToText",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "AudioToText", targets: ["AudioToText"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            exact: "1.1.1"
        )
    ],
    targets: [
        .executableTarget(
            name: "AudioToText",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources/AudioToText",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "AudioToTextTests",
            dependencies: ["AudioToText"],
            path: "Tests/AudioToTextTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
