// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskCleaner",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CleanerCore", targets: ["CleanerCore"]),
        .executable(name: "DiskCleaner", targets: ["DiskCleaner"]),
    ],
    targets: [
        .target(name: "CleanerCore"),
        .executableTarget(
            name: "DiskCleaner",
            dependencies: ["CleanerCore"]
        ),
        .testTarget(
            name: "CleanerCoreTests",
            dependencies: ["CleanerCore"]
        ),
    ]
)
