// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Profile",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Profile", targets: ["Profile"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(
            name: "Profile",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "ProfileTests", dependencies: ["Profile"])
    ]
)
