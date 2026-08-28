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
    }

    private let kind: Kind
    private let tint: Color
    private let scale: CGFloat
    private let rotation: Angle

    /// - Parameter scale: the kit's `h`. A drawing scale, **not** the rendered
    ///   height: the stacked kinds overlap their cap by 2pt, so a dropper drawn
    ///   at 50 stands 39pt tall. Callers that need an exact box should give this
    ///   view a frame.
    public init(
        kind: Kind = .tube,
        tint: Color,
        scale: CGFloat = 96,
        rotation: Angle = .degrees(0)
    ) {
        self.kind = kind
        self.tint = tint
        self.scale = scale
        self.rotation = rotation
    }

    public var body: some View {
        shape
            .rotationEffect(rotation)
            .accessibilityHidden(true)
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
