// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    targets: [
        .target(
            name: "DesignSystem",
            // The script that draws the strands is source, not a resource.
            exclude: ["Resources/hair-strands.py"],
            resources: [
                .copy("Resources/Fonts"),
                // The twelve hair-pattern strands (GLO-248), as an asset
                // catalog so the SVGs stay vector on every scale.
                .process("Resources/Hair.xcassets")
            ]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
    ]
)
