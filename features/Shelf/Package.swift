// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shelf",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Shelf", targets: ["Shelf"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(
            name: "Shelf",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "ShelfTests", dependencies: ["Shelf"])
    ]
)
