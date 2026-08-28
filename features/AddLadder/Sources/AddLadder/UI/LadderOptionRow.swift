import DataKit
import DesignSystem
import SwiftUI

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

    @ViewBuilder
    private var thumb: some View {
        switch option {
        case let .match(hit):
            // The kit draws products, never photographs. `ProductMock` is that
            // drawing; a real cutout lands on top of it when R2 exists.
            ProductMock(
                kind: LadderOptionRow.packaging(for: hit.categorySlug),
                // Seeded on the name, not the category. Seeding both on the
                // category made every blush in the list the same pink dropper,
                // which is visible the moment you look at rung 2 — a screen
                // whose entire instruction is "check the photo, not the name",
                // told to people looking at photos that cannot differ. The
                // colour is still decoration and still claims nothing about the
                // real product; it just stops being the same decoration twice.
                tint: ProductMock.tint(for: hit.name),
                scale: LadderCard.mockScale
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
        case let .match(hit):
            Text(hit.brandName.lowercased()).meta()
            Text(hit.name.lowercased())
                .font(Typography.display(15, weight: 700))
                .foregroundStyle(Tokens.Ink.primary)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 1)
            // The frame puts a variant line and an `EvidenceLine` of face-offs
            // below the name. `search_catalog` returns neither, so the slot
            // stays empty rather than stating a count nobody measured —
            // GLO-63. What does go here is the one fact the row *does* know
            // and that changes what the product means to everyone else.
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
        case let .match(hit):
            hit.scope == .personal
                ? "\(hit.brandName.lowercased()), \(hit.name.lowercased()), yours only"
                : "\(hit.brandName.lowercased()), \(hit.name.lowercased())"
        case let .noneOfThese(prompt):
            prompt
        }
    }

    /// What a category is usually sold in.
    ///
    /// A guess, and labelled one: the catalog records no packaging, so this
    /// reads the category and picks the silhouette the kit drew for that kind
    /// of product. Unknown slugs fall through to `tube`, which is the kit's own
    /// fallthrough — a category we have never seen gets the generic shape
    /// rather than a confident wrong one.
    ///
    /// It is deliberately not a claim about the individual product. A powder
    /// blush in a compact still draws as a dropper here, and that is the cost
    /// of not having the field; GLO-63 carries the fix.
    static func packaging(for categorySlug: String) -> ProductMock.Kind {
        switch categorySlug {
        case "blush", "serum": .dropper
        case "foundation", "cleanser", "styler": .bottle
        case "moisturizer": .jar
        case "fragrance": .mist
        default: .tube
        }
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
