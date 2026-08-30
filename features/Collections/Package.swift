// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Collections",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Collections", targets: ["Collections"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(
            name: "Collections",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "CollectionsTests", dependencies: ["Collections"])
    ]
)
