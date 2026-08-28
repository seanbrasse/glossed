// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ranking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Ranking", targets: ["Ranking"])
    ],
    dependencies: [
        .package(path: "../../core/DesignSystem")
    ],
    targets: [
        .target(name: "Ranking", dependencies: [.product(name: "DesignSystem", package: "DesignSystem")]),
        .testTarget(name: "RankingTests", dependencies: ["Ranking"])
    ]
)
