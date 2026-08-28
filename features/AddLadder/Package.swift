// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AddLadder",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AddLadder", targets: ["AddLadder"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit")
    ],
    targets: [
        .target(name: "AddLadder", dependencies: [.product(name: "DataKit", package: "DataKit")]),
        .testTarget(name: "AddLadderTests", dependencies: ["AddLadder"])
    ]
)
