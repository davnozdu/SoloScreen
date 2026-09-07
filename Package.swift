// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SoloScreen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SoloScreen", targets: ["SoloScreen"]),
        .library(name: "SoloCore", targets: ["SoloCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "SoloCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "SoloScreen",
            dependencies: [
                "SoloCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SoloCoreTests", dependencies: ["SoloCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
