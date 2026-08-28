// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Import",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Import", targets: ["Import"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(
            name: "Import",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "ImportTests", dependencies: ["Import"])
    ]
)
