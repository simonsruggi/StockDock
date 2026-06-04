// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StockDock",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "StockDock",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "StockDock",
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources/AppIcon.icns"),
                .copy("Fonts/InterVariable.ttf")
            ]
        ),
        .testTarget(
            name: "StockDockTests",
            dependencies: ["StockDock"],
            path: "Tests"
        ),
    ]
)
