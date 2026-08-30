// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Browse",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Browse", targets: ["Browse"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(
            name: "Browse",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "BrowseTests", dependencies: ["Browse"])
    ]
)
