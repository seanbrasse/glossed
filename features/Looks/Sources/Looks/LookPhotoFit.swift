import CoreGraphics
import Foundation

/// The geometry of fitting a photo into the post's frame before upload —
/// Sean's Sept 1 ask: *"resize/fit the image in the window during upload."*
///
/// Pure arithmetic so the rules are testable without a screen: the image is
/// drawn centred in the frame at `fillScale × zoom`, panned by `offset`, and
/// **may never leave a gap** — zoom floors at fill, and the offset is clamped
/// to the slack the zoom created. `cropRect` is the frame, mapped back into
/// the photo's own pixels, which is what gets uploaded.
public struct LookPhotoFit: Equatable, Sendable {
    public static let maxZoom: CGFloat = 4

    public let imageSize: CGSize
    public let frameSize: CGSize

    public init(imageSize: CGSize, frameSize: CGSize) {
        self.imageSize = imageSize
        self.frameSize = frameSize
    }

    /// The smallest scale at which the photo covers the whole frame.
    public var fillScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(frameSize.width / imageSize.width, frameSize.height / imageSize.height)
    }

    /// 1 is "fills the frame"; anything under it would show the frame's ground.
    public func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, 1), Self.maxZoom)
    }

    /// How far the image centre may sit from the frame centre at this zoom
    /// before an edge shows: half the overhang on each axis.
    public func slack(at zoom: CGFloat) -> CGSize {
        let scale = fillScale * clampedZoom(zoom)
        return CGSize(
            width: max(0, (imageSize.width * scale - frameSize.width) / 2),
            height: max(0, (imageSize.height * scale - frameSize.height) / 2)
        )
    }

    public func clampedOffset(_ offset: CGSize, at zoom: CGFloat) -> CGSize {
        let room = slack(at: zoom)
        return CGSize(
            width: min(max(offset.width, -room.width), room.width),
            height: min(max(offset.height, -room.height), room.height)
        )
    }

    /// The frame, in the photo's pixel coordinates, for a given zoom and
    /// (already clamped) offset. Integral, and never outside the photo.
    public func cropRect(zoom: CGFloat, offset: CGSize) -> CGRect {
        let scale = fillScale * clampedZoom(zoom)
        let pan = clampedOffset(offset, at: zoom)
        // The image's top-left corner, in frame points.
        let imageLeft = frameSize.width / 2 + pan.width - imageSize.width * scale / 2
        let imageTop = frameSize.height / 2 + pan.height - imageSize.height * scale / 2
        let rect = CGRect(
            x: -imageLeft / scale,
            y: -imageTop / scale,
            width: frameSize.width / scale,
            height: frameSize.height / scale
        )
        let bounds = CGRect(origin: .zero, size: imageSize)
        return rect.integral.intersection(bounds)
    }
}
