import SwiftUI

/// The drawn product — a port of `G.Mock` in the kit's `screens.jsx`.
///
/// The kit never used photographs. Every frame that shows a product shows a
/// tinted vector shaped like its packaging, and that is what the ladder rows,
/// the shelf and the product page were designed around. It is not a placeholder
/// waiting on R2: real cutouts land *on top of* this, and until they do this is
/// the frame rather than a stand-in for it.
///
/// Sitting next to `TypographicTile`, which is the floor of ADR 0004's chain:
/// the tile is what a product with no photo *and no known packaging* looks
/// like. This is what one whose packaging we do know looks like.
///
/// Like every primitive here, it knows nothing about products — the caller
/// picks the `kind` and the `tint`.
public struct ProductMock: View {
    /// The five silhouettes the kit draws, plus `mist`. `tube` is the fallback
    /// the kit falls through to, so it is the default here too.
    public enum Kind: String, CaseIterable, Sendable {
        case tube, bottle, dropper, jar, compact, mist

        /// What a category is usually sold in — the silhouette the kit drew
        /// for that kind of product.
        ///
        /// A guess, and labelled one: the catalog records no packaging
        /// (GLO-14 owns adding it), so this reads the category. It is
        /// deliberately not a claim about the individual product — a powder
        /// blush in a compact still draws as a dropper.
        ///
        /// Lives on the primitive because two features (the ladder's match
        /// rows, the shelf's bays) draw products by category and features may
        /// not import each other. Two copies of this table is how the same
        /// product comes to draw as two shapes on two screens.
        ///
        /// Unknown slugs fall through to `tube`, the kit's own fallthrough —
        /// a category we have never seen gets the generic shape rather than a
        /// confident wrong one.
        public static func usual(forCategory slug: String) -> Kind {
            switch slug {
            case "blush", "serum": .dropper
            case "foundation", "cleanser", "styler": .bottle
            case "moisturizer": .jar
            case "fragrance": .mist
            default: .tube
            }
        }
    }

    private let kind: Kind
    private let tint: Color
    private let scale: CGFloat
    private let rotation: Angle
    private let label: String?

    /// - Parameter scale: the kit's `h`. A drawing scale, **not** the rendered
    ///   height: the stacked kinds overlap their cap by 2pt, so a dropper drawn
    ///   at 50 stands 39pt tall. Callers that need an exact box should give this
    ///   view a frame.
    /// - Parameter label: a short sticker across the object's waist — the shelf
    ///   puts `#1` there. Two or three characters; it does not wrap and does not
    ///   shrink the drawing to fit, because a mock that resizes to its label
    ///   stops being comparable to the one beside it.
    public init(
        kind: Kind = .tube,
        tint: Color,
        scale: CGFloat = 96,
        rotation: Angle = .degrees(0),
        label: String? = nil
    ) {
        self.kind = kind
        self.tint = tint
        self.scale = scale
        self.rotation = rotation
        self.label = label
    }

    public var body: some View {
        drawing
            .rotationEffect(rotation)
    }

    /// Unlabelled, the mock is decoration and says nothing a screen reader has
    /// not already heard: whatever row it sits in carries the brand and the
    /// name. Labelled, the sticker is the only thing on it that is readable at
    /// all, and on the shelf it is the item's rank — so that is what it says.
    @ViewBuilder
    private var drawing: some View {
        if let label {
            shape
                .overlay(alignment: .center) { sticker(label) }
                .accessibilityElement()
                .accessibilityLabel(ProductMock.spoken(label))
        } else {
            shape.accessibilityHidden(true)
        }
    }

    /// The kit centres this at 54% of the object's height — a shade below the
    /// middle, which is where a label sits on a real bottle rather than exactly
    /// halfway up it. Offset from centre rather than measured, because the
    /// drawn height varies by kind and 4% of it is under half a point.
    ///
    /// The drawing lives in `ProductSticker` so a real photo (`ProductImage`)
    /// wears the identical label — two sticker styles in one bay would read as
    /// two kinds of rank.
    private func sticker(_ text: String) -> some View {
        ProductSticker(text: text, scale: scale)
    }

    /// How wide this draws, in points.
    ///
    /// The widest piece wins: a jar's lid is narrower than its body, a dropper's
    /// cap is much narrower than its bottle. Callers laying mocks out beside
    /// each other need the silhouette's footprint, not a nominal size.
    ///
    /// Deliberately *not* the label's width. A brand sticker is wider than the
    /// bottle it is stuck to — that is what a label looks like — and letting it
    /// widen the object would make a long brand name push its neighbours around.
    /// A caller packing mocks tightly enough for stickers to collide should give
    /// them a floor of its own.
    public nonisolated static func drawnWidth(kind: Kind, scale: CGFloat) -> CGFloat {
        scale * widestFraction(kind)
    }

    /// The `width` fractions in `shape`, largest per kind. Kept next to the
    /// drawing rather than derived from it: `Piece` is a private detail and a
    /// `View` cannot be measured without rendering it.
    private nonisolated static func widestFraction(_ kind: Kind) -> CGFloat {
        switch kind {
        case .compact: 0.8
        case .jar: 0.66
        case .bottle: 0.42
        case .dropper: 0.36
        case .mist: 0.32
        case .tube: 0.28
        }
    }

    /// `#2` read aloud as "hash two" is noise. Only the shelf uses this today
    /// and its labels are ranks, so the `#` becomes the word that explains it.
    nonisolated static func spoken(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return trimmed }
        return "ranked \(trimmed.dropFirst())"
    }

    @ViewBuilder
    private var shape: some View {
        switch kind {
        case .compact:
            // The one kind that is a single piece: a pan seen from above.
            draw(Piece(0.8, 0.8, scale * 0.4))
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .overlay(Circle().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin))
                        .padding(scale * 0.16)
                )
        case .jar:
            stack(cap: Piece(0.58, 0.2, 7, ProductMock.creamCap), body: Piece(0.66, 0.48, 12))
        case .dropper:
            stack(cap: Piece(0.2, 0.2, 6, ProductMock.darkCap), body: Piece(0.36, 0.62, 10))
        case .mist:
            stack(cap: Piece(0.18, 0.24, 5, ProductMock.creamCap), body: Piece(0.32, 0.6, 9))
        case .bottle:
            stack(cap: Piece(0.16, 0.14, 4, ProductMock.creamCap), body: Piece(0.42, 0.68, 11))
        case .tube:
            stack(cap: Piece(0.22, 0.2, 5, ProductMock.creamCap), body: Piece(0.28, 0.66, 8))
        }
    }

    /// One rectangle of a mock, in the kit's own units: width and height as
    /// fractions of `scale`, corner radius in points, and a fill that overrides
    /// the product tint (caps are made of cap material, not of the product).
    private struct Piece {
        let width, height, radius: CGFloat
        let fill: Color?

        init(_ width: CGFloat, _ height: CGFloat, _ radius: CGFloat, _ fill: Color? = nil) {
            self.width = width
            self.height = height
            self.radius = radius
            self.fill = fill
        }
    }

    /// Cap over body, overlapping by 2pt so the two read as one object rather
    /// than as two rectangles that happen to touch.
    private func stack(cap: Piece, body: Piece) -> some View {
        VStack(spacing: -2) {
            draw(cap).zIndex(1)
            draw(body)
        }
    }

    private func draw(_ piece: Piece) -> some View {
        RoundedRectangle(cornerRadius: piece.radius)
            .fill(piece.fill ?? tint)
            .frame(width: scale * piece.width, height: scale * piece.height)
            .overlay(
                RoundedRectangle(cornerRadius: piece.radius)
                    .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
            )
            .background(
                RoundedRectangle(cornerRadius: piece.radius)
                    .fill(Tokens.Ink.primary)
                    .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
            )
    }

    // The kit writes these two as literals inside `G.Mock` rather than as
    // tokens, because they are not part of the palette — they are what a cap is
    // made of. Ported as literals for the same reason.
    private static let creamCap = Color(hex: 0xF1EDE4)
    private static let darkCap = Color(hex: 0x3A342E)
}

public extension ProductMock {
    /// The palette a mock can land on when nothing is known about the real
    /// product's colour, and the rule that picks one.
    ///
    /// Deliberately the same shape as `TypographicTile.tint(for:)` — including
    /// the reason it is not `hashValue`: Swift seeds that per process, so a
    /// product would change colour every launch and a shelf would look
    /// reshuffled when nothing had moved.
    nonisolated static let tints: [Color] = [
        Color(hex: 0xD4788C), // rose
        Color(hex: 0xE5C6A8), // sand
        Color(hex: 0xC9C3E4), // wisteria
        Color(hex: 0xBCD3C4), // sage
        Color(hex: 0xE7E2D6) // bone
    ]

    nonisolated static func tint(for seed: String) -> Color {
        tints[tintIndex(for: seed)]
    }

    /// Returned as an index rather than a `Color` so the rule can be tested —
    /// comparing two SwiftUI `Color` values traps in a headless test process.
    nonisolated static func tintIndex(for seed: String) -> Int {
        let total = seed.unicodeScalars.reduce(0) { sum, scalar in
            (sum &+ Int(scalar.value)) % 100_003
        }
        return total % tints.count
    }
}
