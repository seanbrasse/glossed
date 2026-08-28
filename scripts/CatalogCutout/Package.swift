// swift-tools-version: 6.0
import PackageDescription

/// GLO-48 · the batch half of the image pipeline: catalog images are processed
/// once at ingest, never at render (tech/01 §7). Vision on our own Mac was the
/// PRD's named alternative to rembg (§08), and it is also the exact API the
/// app's on-device cutouts will use — one background-removal behavior, not two.
let package = Package(
    name: "CatalogCutout",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CatalogCutout", path: "Sources")
    ]
)
