// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stylist",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Stylist", targets: ["Stylist"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem"),
        .package(path: "../../core/Tracking")
    ],
    targets: [
        .target(
            name: "Stylist",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Tracking", package: "Tracking")
            ]
        ),
        .testTarget(name: "StylistTests", dependencies: ["Stylist"])
    ]
)
