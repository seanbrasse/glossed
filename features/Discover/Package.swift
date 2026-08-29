// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Discover",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Discover", targets: ["Discover"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(
            name: "Discover",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "DiscoverTests", dependencies: ["Discover"])
    ]
)
