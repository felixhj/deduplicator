// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DedupCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DedupCore", targets: ["DedupCore"]),
    ],
    targets: [
        .target(name: "DedupCore"),
        .testTarget(name: "DedupCoreTests", dependencies: ["DedupCore"]),
    ]
)
