// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Media",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Media", targets: ["Media"])
    ],
    targets: [
        .target(name: "Media"),
        .testTarget(name: "MediaTests", dependencies: ["Media"])
    ]
)
