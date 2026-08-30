// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Routines",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Routines", targets: ["Routines"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem"),
        .package(path: "../../core/Tracking")
    ],
    targets: [
        .target(
            name: "Routines",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem"),
                .product(name: "Tracking", package: "Tracking")
            ]
        ),
        .testTarget(name: "RoutinesTests", dependencies: ["Routines"])
    ]
)
