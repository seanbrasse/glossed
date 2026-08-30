// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Looks",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Looks", targets: ["Looks"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem"),
        .package(path: "../../core/Media")
    ],
    targets: [
        .target(
            name: "Looks",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Media", package: "Media")
            ]
        ),
        .testTarget(name: "LooksTests", dependencies: ["Looks"])
    ]
)
