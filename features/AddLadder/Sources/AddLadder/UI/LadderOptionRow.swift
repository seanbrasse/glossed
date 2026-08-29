import DataKit
import DesignSystem
import SwiftUI

/// Where catalog image keys become URLs, set once by the app shell. Nil —
/// previews, fixtures, a shell without config — renders the drawn mock,
/// which is the chain's floor anyway (GLO-83).
public extension EnvironmentValues {
    @Entry var catalogImageBase: URL?
}

public extension CatalogHit {
    /// The hit's cutout as a fetchable URL, or nil when either half is
    /// missing. Composition lives with the consumer because the key is
    /// storage-relative on purpose — moving the bucket touches no schema.
    func catalogImageURL(base: URL?) -> URL? {
        guard let base, let catalogImageKey else { return nil }
        return base.appending(path: catalogImageKey)
    }
}

/// One row of a rung's option list, built to the `card` and `noneOfThese`
/// helpers inside `G.AddLadder` in the kit's `screens.jsx`.
///
/// The two share every dimension — border, radius, shadow, padding, gap, and a
/// 46pt thumb slot — and differ in exactly two things the frame is explicit
/// about: the escape row is tinted `butter-soft`, and its thumb slot is a
/// dashed square holding the search glyph rather than a drawn product.
///
/// That is the point the screen map's caption makes: *"'none of these' carries
/// the same weight as a match at every rung."* Same weight, not camouflage —
/// which is what shipping the two as visually identical produced, and what
/// GLO-62 exists to undo.
public struct LadderOptionRow: View {
    private let option: LadderOption
    private let action: () -> Void

    public init(_ option: LadderOption, action: @escaping () -> Void) {
        self.option = option
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: LadderCard.gap) {
                thumb
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: Tokens.hitTarget)
            .ladderCard(tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @Environment(\.catalogImageBase) private var imageBase

    @ViewBuilder
    private var thumb: some View {
        switch option {
        case let .match(hit, _):
            // The real cutout when the catalog has one (GLO-83 — "check the
            // photo" finally means a photo); the drawn mock stands in below.
            // Tint seeded on the name, not the category: seeding on the
            // category made every blush in the list the same pink dropper,
            // on the one screen whose instruction is "check the photo".
            ProductImage(
                catalog: hit.catalogImageURL(base: imageBase),
                kind: LadderOptionRow.packaging(for: hit.categorySlug),
                tint: ProductMock.tint(for: hit.name),
                scale: LadderCard.mockScale,
                maxWidth: LadderCard.thumbWidth
            )
            .frame(width: LadderCard.thumbWidth)
        case .noneOfThese:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Tokens.Ink.primary)
                .frame(width: LadderCard.thumbWidth, height: LadderCard.thumbHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(
                            Tokens.Ink.primary,
                            style: StrokeStyle(lineWidth: Tokens.Border.thin, dash: [4, 3])
                        )
                )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch option {
        case let .match(hit, reason):
            Text(hit.brandName.lowercased()).meta()
            Text(hit.name.lowercased())
                .font(Typography.display(15, weight: 700))
                .foregroundStyle(Tokens.Ink.primary)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 1)
            // The frame's card, finally whole (GLO-63): the variant line when
            // the product has exactly one, then the sub-slot — the near
            // rung's server-computed reason, or the search rung's evidence
            // line. Absent facts stay absent: no reason is invented, and an
            // absent count renders nothing rather than "0 face-offs".
            if let variant = hit.variantLabel {
                Text(variant).meta()
            }
            if let reason {
                Text(reason).meta(color: Tokens.Cherry.deep).padding(.top, 2)
            } else if let count = hit.faceOffCount {
                EvidenceLine(n: count, label: "face-offs").padding(.top, 2)
            }
            if hit.scope == .personal {
                Badge("yours only", tone: .lilac).padding(.top, 3)
            }
        case let .noneOfThese(prompt):
            Text(prompt)
                .font(Typography.display(15, weight: 700))
                .foregroundStyle(Tokens.Ink.primary)
                .multilineTextAlignment(.leading)
            Text("keep going — the next rung is one tap")
                .meta()
                .padding(.top, 1)
        }
    }

    private var tint: Color {
        switch option {
        case .match: Tokens.Ground.card
        case .noneOfThese: Tokens.Support.butterSoft
        }
    }

    private var accessibilityLabel: String {
        switch option {
        case let .match(hit, _):
            hit.scope == .personal
                ? "\(hit.brandName.lowercased()), \(hit.name.lowercased()), yours only"
                : "\(hit.brandName.lowercased()), \(hit.name.lowercased())"
        case let .noneOfThese(prompt):
            prompt
        }
    }

    /// One table, on the primitive — see `ProductMock.Kind.usual(forCategory:)`.
    /// The shelf draws by category too, and two copies of the table is how the
    /// same product comes to draw as two shapes on two screens.
    static func packaging(for categorySlug: String) -> ProductMock.Kind {
        ProductMock.Kind.usual(forCategory: categorySlug)
    }
}

/// The card both rows are made of, at the frame's own numbers.
///
/// Not `GlossedCard`: the frame's ladder card is radius 16 with asymmetric
/// 12/13 padding, and `GlossedCard` is radius 18 (`--radius-lg`) with uniform
/// padding. Rounding to the nearest token is exactly the substitution GLO-62 is
/// a rework of, so the frame's numbers win here and are named rather than
/// scattered.
///
/// Worth a decision from someone who owns the kit: `G.AddLadder` writes 16 and
/// `12px 13px` as literals even though the kit *has* radius tokens. Either the
/// kit should tokenize them or the card should move to `--radius-lg`. Until
/// then, matching the drawing is the safer of the two errors.
enum LadderCard {
    static let radius: CGFloat = 16
    static let paddingVertical: CGFloat = 12
    static let paddingHorizontal: CGFloat = 13
    static let gap: CGFloat = 12
    static let thumbWidth: CGFloat = 46
    static let thumbHeight: CGFloat = 50
    static let mockScale: CGFloat = 50
}

extension View {
    /// Border, radius, shadow and padding are identical for every row. Only the
    /// fill is passed in, so a future row cannot quietly acquire a lighter
    /// border and stop reading as a peer.
    func ladderCard(tint: Color) -> some View {
        padding(.vertical, LadderCard.paddingVertical)
            .padding(.horizontal, LadderCard.paddingHorizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: LadderCard.radius))
            .overlay(
                RoundedRectangle(cornerRadius: LadderCard.radius)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
            )
            .background(
                RoundedRectangle(cornerRadius: LadderCard.radius)
                    .fill(Tokens.Ink.primary)
                    .offset(x: Tokens.Shadow.md, y: Tokens.Shadow.md)
            )
    }
}
