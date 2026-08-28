// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProductPage",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ProductPage", targets: ["ProductPage"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(
            name: "ProductPage",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "ProductPageTests", dependencies: ["ProductPage"])
    ]
)
