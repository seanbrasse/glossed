// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tracking",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Tracking", targets: ["Tracking"])
    ],
    targets: [
        // No dependencies on purpose. The transport is injected (a closure the
        // app wires to the track_ingest function), so this package cannot grow
        // a path to the data layer — analytics that can read the shelf is the
        // boundary tech/06 exists to prevent.
        .target(name: "Tracking"),
        .testTarget(name: "TrackingTests", dependencies: ["Tracking"])
    ]
)
