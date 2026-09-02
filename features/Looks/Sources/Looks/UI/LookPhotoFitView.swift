import DesignSystem
import SwiftUI

/// Fit a photo into the post's frame before it uploads: pinch to zoom, drag
/// to pan, and what the frame shows is what gets saved. The arithmetic lives
/// in `LookPhotoFit`; this view only holds the gestures and renders the crop.
///
/// The frame's aspect is the deck card's, because that is how the post shows
/// the photo. The profile's square tile takes its centre.
public struct LookPhotoFitView: View {
    private let imageData: Data
    private let aspect: CGFloat
    private let onDone: (Data) -> Void
    private let onCancel: () -> Void

    @State private var zoom: CGFloat = 1
    /// The pan as a FRACTION of the frame's width, not points: the frame is
    /// laid out live and the crop is computed in the photo's own pixels, so
    /// the one unit that means the same in both places is "how far across".
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    public init(
        imageData: Data,
        aspect: CGFloat = LookDeckGeometry.cardWidth / LookDeckGeometry.cardHeight,
        onDone: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.imageData = imageData
        self.aspect = aspect
        self.onDone = onDone
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            Text("fit the photo")
                .font(Typography.display(Typography.Size.h3))
                .foregroundStyle(Tokens.Ink.primary)
            Text("pinch to zoom, drag to move. what the frame shows is what posts.")
                .meta()
            frame
            HStack(spacing: Tokens.Space.s3) {
                Button("cancel", action: onCancel)
                    .buttonStyle(.glossed(.secondary, size: .sm))
                Button("use this") { save() }
                    .buttonStyle(.glossed(block: true))
            }
        }
        .padding(Tokens.Space.s5)
        .background(Tokens.Ground.milk.ignoresSafeArea())
    }

    private var frame: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    canvas(in: proxy.size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.hair)
            )
    }

    @ViewBuilder
    private func canvas(in size: CGSize) -> some View {
        #if canImport(UIKit)
            if let image = UIImage(data: imageData) {
                let fit = LookPhotoFit(imageSize: image.size, frameSize: size)
                let liveZoom = fit.clampedZoom(zoom * pinch)
                let base = Self.points(offset, in: size)
                let livePan = fit.clampedOffset(
                    CGSize(width: base.width + drag.width, height: base.height + drag.height),
                    at: liveZoom
                )
                Image(uiImage: image)
                    .resizable()
                    .frame(
                        width: image.size.width * fit.fillScale * liveZoom,
                        height: image.size.height * fit.fillScale * liveZoom
                    )
                    .position(x: size.width / 2 + livePan.width, y: size.height / 2 + livePan.height)
                    .gesture(gestures(fit, in: size))
                    .accessibilityLabel("the photo, zoomed and moved to fit")
            } else {
                Rectangle().fill(Tokens.Support.lilacSoft)
            }
        #else
            Rectangle().fill(Tokens.Support.lilacSoft)
        #endif
    }

    private func gestures(_ fit: LookPhotoFit, in size: CGSize) -> some Gesture {
        let magnify = MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                zoom = fit.clampedZoom(zoom * value.magnification)
                offset = Self.fraction(fit.clampedOffset(Self.points(offset, in: size), at: zoom), in: size)
            }
        let pan = DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let base = Self.points(offset, in: size)
                let moved = CGSize(
                    width: base.width + value.translation.width,
                    height: base.height + value.translation.height
                )
                offset = Self.fraction(fit.clampedOffset(moved, at: zoom), in: size)
            }
        return magnify.simultaneously(with: pan)
    }

    private static func points(_ fraction: CGSize, in frame: CGSize) -> CGSize {
        CGSize(width: fraction.width * frame.width, height: fraction.height * frame.width)
    }

    private static func fraction(_ points: CGSize, in frame: CGSize) -> CGSize {
        guard frame.width > 0 else { return .zero }
        return CGSize(width: points.width / frame.width, height: points.height / frame.width)
    }

    private func save() {
        #if canImport(UIKit)
            guard let image = UIImage(data: imageData) else { return onCancel() }
            // The on-screen frame is not known here, only its aspect. A frame
            // of the photo's own width has the same proportions, and the pan is
            // a fraction of the width, so the crop comes out in pixels exactly.
            let frameSize = CGSize(width: image.size.width, height: image.size.width / aspect)
            let fit = LookPhotoFit(imageSize: image.size, frameSize: frameSize)
            let rect = fit.cropRect(zoom: zoom, offset: Self.points(offset, in: frameSize))
            guard let data = Self.crop(image, to: rect) else { return onCancel() }
            onDone(data)
        #else
            onCancel()
        #endif
    }

    #if canImport(UIKit)
        /// Draw upright first — a phone photo's pixels are often rotated and
        /// carry an orientation flag that `cgImage.cropping` ignores.
        private static func crop(_ image: UIImage, to rect: CGRect) -> Data? {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
            guard let cg = upright.cgImage?.cropping(to: rect) else { return nil }
            return UIImage(cgImage: cg).jpegData(compressionQuality: 0.92)
        }
    #endif
}
