// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Bubble",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Bubble",
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
