// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "treedocs",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.1"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.1"),
    ],
    targets: [
        .executableTarget(
            name: "treedocs",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "PathKit", package: "PathKit"),
            ]
        ),
        .testTarget(
            name: "treedocsTests",
            dependencies: [
                "treedocs",
                .product(name: "Yams", package: "Yams"),
                .product(name: "PathKit", package: "PathKit"),
            ]
        ),
    ]
)
