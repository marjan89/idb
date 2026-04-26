// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "idb",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "idb",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/idb"
        ),
        .testTarget(
            name: "idbTests",
            dependencies: ["idb"],
            path: "Tests"
        ),
    ]
)
