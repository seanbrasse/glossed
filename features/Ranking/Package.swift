// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ranking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Ranking", targets: ["Ranking"])
    ],
    targets: [
        .target(name: "Ranking"),
        .testTarget(name: "RankingTests", dependencies: ["Ranking"])
    ]
)
