// swift-tools-version: 6.0
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
        .package(url: "https://github.com/ajevans99/swift-json-schema", from: "0.13.1"),
        .package(url: "https://github.com/tuist/Noora", from: "0.56.0"),
        .package(url: "https://github.com/onevcat/Rainbow", from: "4.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "treedocs",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "Noora", package: "Noora"),
                .product(name: "Rainbow", package: "Rainbow"),
            ],
            resources: [
                .copy("../../site/schemas/0.1.0/treedocs-0.1.0.schema.json"),
                .copy("../../site/schemas/0.2.0/treedocs-0.2.0.schema.json"),
                .copy("Resources/descriptions-suggestions.yaml"),
            ]
        ),
        .testTarget(
            name: "treedocsTests",
            dependencies: [
                "treedocs",
                .product(name: "Yams", package: "Yams"),
                .product(name: "PathKit", package: "PathKit"),
                .product(name: "JSONSchema", package: "swift-json-schema"),
                .product(name: "Rainbow", package: "Rainbow"),
            ]
        ),
    ]
)
