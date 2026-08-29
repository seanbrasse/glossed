// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Privacy",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Privacy", targets: ["Privacy"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(
            name: "Privacy",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "PrivacyTests", dependencies: ["Privacy"])
    ]
)
