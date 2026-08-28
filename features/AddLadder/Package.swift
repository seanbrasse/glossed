// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AddLadder",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AddLadder", targets: ["AddLadder"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem"),
        .package(path: "../../core/Tracking")
    ],
    targets: [
        .target(
            name: "AddLadder",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Tracking", package: "Tracking")
            ]
        ),
        .testTarget(name: "AddLadderTests", dependencies: ["AddLadder"])
    ]
)
