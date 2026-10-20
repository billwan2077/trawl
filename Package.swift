// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Trawl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Trawl", targets: ["Trawl"]),
        .library(name: "TrawlCore", targets: ["TrawlCore"]),
    ],
    targets: [
        .target(name: "TrawlCore"),
        .executableTarget(name: "Trawl", dependencies: ["TrawlCore"]),
        .testTarget(name: "TrawlCoreTests", dependencies: ["TrawlCore"]),
    ]
)
