// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "treedocs",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "treedocs", targets: ["treedocs"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.1"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.1"),
        .package(url: "https://github.com/kylef/JSONSchema.swift", from: "0.6.0"),
        .package(url: "https://github.com/tuist/Noora", from: "0.56.0"),
        .package(url: "https://github.com/onevcat/Rainbow", from: "4.2.1"),
        .package(
            url: "https://github.com/DandyLyons/md-utils.git",
            revision: "32c82230a4487bca8e23120a9b7cc2499d40bed9"
        ),
    ],
    targets: [
        .executableTarget(
            name: "treedocs",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "JSONSchema", package: "JSONSchema.swift"),
                .product(name: "Noora", package: "Noora"),
                .product(name: "Rainbow", package: "Rainbow"),
                .product(name: "MarkdownUtilitiesCore", package: "md-utils"),
            ],
            resources: [
                .copy("../../site/schemas/0.1.0/treedocs-0.1.0.schema.json"),
                .copy("../../site/schemas/0.2.0/treedocs-0.2.0.schema.json"),
                .copy("../../site/schemas/0.3.0-WIP/treedocs-0.3.0-WIP.schema.json"),
                .copy("Resources/descriptions-suggestions.yaml"),
            ]
        ),
        .testTarget(
            name: "treedocsTests",
            dependencies: [
                "treedocs",
                .product(name: "Yams", package: "Yams"),
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "JSONSchema", package: "JSONSchema.swift"),
                .product(name: "Rainbow", package: "Rainbow"),
            ]
        ),
    ]
)
