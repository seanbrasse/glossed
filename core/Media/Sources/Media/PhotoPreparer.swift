import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo that is safe to leave the device: metadata stripped, bounded in
/// size, re-encoded. The ONLY way user photo bytes should reach an upload.
public struct PreparedPhoto: Sendable, Equatable {
    public let jpegData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
}

public enum PhotoPreparationError: Error, Equatable {
    /// The bytes are not an image this device can decode.
    case undecodable
    /// The on-device sensitive-content check said no. The photo never left
    /// the device and never will — the caller shows the refusal, not us.
    case blockedByContentCheck
}

/// The on-device screening seam (tech/03 §1: SensitiveContentAnalysis at
/// selection). A protocol because the framework needs an entitlement, is
/// unavailable in extensions and on the simulator, and the composer must be
/// drivable without it — the app wires the real checker; fixtures pass one
/// that always answers.
public protocol SensitiveContentChecking: Sendable {
    /// True = allowed. A throwing checker fails CLOSED at the call site.
    func isAllowed(_ imageData: Data) async throws -> Bool
}

/// The always-allowed stub — previews, the simulator, tests. Naming it
/// loudly beats a default parameter: the app must CHOOSE it, visibly.
public struct AlwaysAllowedChecker: SensitiveContentChecking {
    public init() {}
    public func isAllowed(_: Data) async throws -> Bool {
        true
    }
}

/// EXIF strip + downscale + re-encode, in that conceptual order (one pass in
/// practice). GLO-198; the documented contract of this package (tech/00 §4).
public struct PhotoPreparer: Sendable {
    /// The longest edge a prepared photo keeps. 2048 holds full-screen
    /// quality on any current device while capping upload size; a feed
    /// render never needs more.
    public static let maxPixelEdge = 2048

    private let checker: any SensitiveContentChecking

    public init(checker: any SensitiveContentChecking) {
        self.checker = checker
    }

    /// The pipeline the spec names: screen on device → strip → bound → JPEG.
    ///
    /// The strip is not an EXIF-only edit: `kCGImageDestinationMetadata` is
    /// simply never written, so GPS, capture time, device model and every
    /// other tag are absent from the output rather than blanked — absence
    /// cannot be un-redacted by a smarter reader.
    public func prepare(_ imageData: Data) async throws -> PreparedPhoto {
        // Fails closed: a checker that errors blocks the photo. A screening
        // step that fails open is not a screening step.
        let allowed = await (try? checker.isAllowed(imageData)) ?? false
        guard allowed else { throw PhotoPreparationError.blockedByContentCheck }

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw PhotoPreparationError.undecodable
        }
        // Thumbnail-from-source both decodes and bounds in one step, and it
        // honors orientation by BAKING it into pixels — necessary, because
        // the orientation tag is metadata and we are not carrying any.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelEdge
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoPreparationError.undecodable
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw PhotoPreparationError.undecodable
        }
        // 0.85: visually clean for skin tones, roughly a third the bytes of
        // 1.0. Worth a workshop only if uploads feel slow in the beta.
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoPreparationError.undecodable
        }

        return PreparedPhoto(
            jpegData: output as Data,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }
}
