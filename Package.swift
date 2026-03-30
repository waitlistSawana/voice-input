// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoiceInputCore", targets: ["VoiceInputCore"]),
        .library(name: "VoiceInputUI", targets: ["VoiceInputUI"]),
        .executable(name: "VoiceInputApp", targets: ["VoiceInputApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3")
    ],
    targets: [
        .target(
            name: "VoiceInputCore",
            path: "Sources/Core"
        ),
        .target(
            name: "VoiceInputUI",
            dependencies: ["VoiceInputCore"],
            path: "Sources/UI",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "VoiceInputApp",
            dependencies: ["VoiceInputCore", "VoiceInputUI"],
            path: "Sources/AppMain",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(
            name: "VoiceInputTests",
            dependencies: [
                "VoiceInputCore",
                "VoiceInputUI",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests"
        )
    ]
)
