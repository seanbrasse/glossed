// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DataKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DataKit", targets: ["DataKit"])
    ],
    dependencies: [
        // Platform client for the backend chosen in ADR 0001.
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.1")
    ],
    targets: [
        .target(name: "DataKit", dependencies: [.product(name: "Supabase", package: "supabase-swift")]),
        .testTarget(name: "DataKitTests", dependencies: ["DataKit"])
    ]
)
