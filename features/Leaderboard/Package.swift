// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Leaderboard",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Leaderboard", targets: ["Leaderboard"])
    ],
    dependencies: [
        .package(path: "../../core/DataKit"),
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(
            name: "Leaderboard",
            dependencies: [
                .product(name: "DataKit", package: "DataKit"),
                .product(name: "DesignSystem", package: "DesignSystem")
            ]
        ),
        .testTarget(name: "LeaderboardTests", dependencies: ["Leaderboard"])
    ]
)
