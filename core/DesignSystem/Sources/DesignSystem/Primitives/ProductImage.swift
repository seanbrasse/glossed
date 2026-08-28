import SwiftUI

/// PRD §08's render rule as one component: **your cutout → the catalog
/// cutout → the drawn mock**. Nobody ever sees a broken image.
///
/// The mock is the floor and the placeholder: it renders while a photo loads
/// and whenever every URL has failed, at the same drawn height, so a bay
/// never jumps when the network answers. Shadow is applied here, in-app —
/// never inherited from the source photo (PRD §08) — and only under photos:
/// the mock's ink outline is its own grounding.
///
/// The caller passes URLs in fallback order; this type does not know buckets
/// or keys. Photos keep the mock's rank sticker, drawn by the same view.
public struct ProductImage: View {
    private let sources: [URL]
    private let kind: ProductMock.Kind
    private let tint: Color
    private let scale: CGFloat
    /// A width limit tighter than the envelope, when the caller has one —
    /// the shelf's size buckets (GLO-82) pass theirs so a bay's slot and its
    /// render are the same number. Nil means the envelope alone applies.
    private let maxWidth: CGFloat?
    private let rotation: Angle
    private let label: String?

    /// URLs that answered with anything other than an image. Per-view state:
    /// a retry is a fresh view identity (a re-opened screen), which is the
    /// right cadence for "try the network again".
    @State private var exhausted: Set<URL> = []

    public init(
        cutout: URL? = nil,
        catalog: URL? = nil,
        kind: ProductMock.Kind,
        tint: Color,
        scale: CGFloat,
        maxWidth: CGFloat? = nil,
        rotation: Angle = .zero,
        label: String? = nil
    ) {
        sources = [cutout, catalog].compactMap(\.self)
        self.kind = kind
        self.tint = tint
        self.scale = scale
        self.maxWidth = maxWidth
        self.rotation = rotation
        self.label = label
    }

    public var body: some View {
        if let url = sources.first(where: { !exhausted.contains($0) }) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    photo(image)
                case .failure:
                    floor.onAppear { exhausted.insert(url) }
                case .empty:
                    floor
                @unknown default:
                    floor
                }
            }
        } else {
            floor
        }
    }

    /// No photo draws wider than this × its drawn height (GLO-82). The mock
    /// silhouettes' own envelope: nothing the kit draws is wider than tall,
    /// and a carton shot that is must not dominate a bay by area. Public so
    /// the shelf's slot packing can reserve exactly what will render.
    public static let maxPhotoAspect: CGFloat = 1.25

    private func photo(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            // Fit inside the height band *and* the width cap: a tall bottle
            // keeps its full height; a wide carton gives up height instead of
            // taking the shelf. Wide things are short — the cap is also the
            // more accurate reading of the photo.
            .frame(
                maxWidth: min(maxWidth ?? .infinity, scale * ProductImage.maxPhotoAspect),
                maxHeight: scale
            )
            .frame(height: scale, alignment: .bottom)
            .shadow(color: Tokens.Ink.primary.opacity(0.22), radius: 3, x: 0, y: 2)
            .overlay(alignment: .center) {
                if let label {
                    ProductSticker(text: label, scale: scale)
                }
            }
            .rotationEffect(rotation)
            .accessibilityElement()
            .accessibilityLabel(label.map(ProductMock.spoken) ?? "")
    }

    private var floor: some View {
        ProductMock(kind: kind, tint: tint, scale: scale, rotation: rotation, label: label)
    }
}

/// The rank sticker, shared by the drawn mock and the real photo so the two
/// can stand in one bay without the labels disagreeing about what a label is.
struct ProductSticker: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        Text(text)
            .font(Typography.mono(7.5))
            .foregroundStyle(Tokens.Ink.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.vertical, 1)
            .padding(.horizontal, 4)
            .background(Tokens.Ground.card)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: 1)
            )
            .offset(y: scale * 0.033)
    }
}
