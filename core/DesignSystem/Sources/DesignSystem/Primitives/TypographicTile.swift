import SwiftUI

/// The floor of the image fallback chain: user photo → catalog image →
/// typographic tile (ADR 0004). Nobody ever sees a broken image, and nobody
/// ever sees an empty grey box either.
///
/// It knows nothing about products — a brand to letter, and a seed to colour
/// by. DesignSystem imports nothing app-specific, so the caller decides what
/// the seed is (a category slug, today).
///
/// The two rules are `nonisolated`: they are arithmetic on a string, and a
/// `View`'s static members are otherwise main-actor isolated, which makes them
/// awkward to call from anywhere that is not already on it.
public struct TypographicTile: View {
    /// The palette a tile can land on. Soft tints only: a tile is a stand-in
    /// for a photo, not a thing competing with one.
    nonisolated static let tints: [Color] = [
        Tokens.Support.lilacSoft,
        Tokens.Support.butterSoft,
        Tokens.Support.mintSoft,
        Tokens.Cherry.soft
    ]

    private let brand: String
    private let seed: String
    private let size: CGFloat

    public init(brand: String, seed: String, size: CGFloat = 52) {
        self.brand = brand
        self.seed = seed
        self.size = size
    }

    public var body: some View {
        Text(TypographicTile.letters(of: brand))
            .font(Typography.display(size * 0.38))
            .foregroundStyle(Tokens.Ink.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, Tokens.Space.s1)
            .frame(width: size, height: size)
            .background(TypographicTile.tint(for: seed))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.md)
                    .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
            )
            .accessibilityLabel("\(brand), no photo yet")
    }

    /// Up to two initials — one word gives one letter, so "Glossier" reads as
    /// G rather than GL, which would look like an abbreviation of something.
    nonisolated static func letters(of brand: String) -> String {
        let words = brand.split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        let initials = words.prefix(2).compactMap(\.first)
        guard !initials.isEmpty else { return "?" }
        return String(initials).uppercased()
    }

    nonisolated static func tint(for seed: String) -> Color {
        tints[tintIndex(for: seed)]
    }

    /// Same product, same colour, every launch — on every device.
    ///
    /// Swift's `hashValue` is seeded per process, so using it here would give a
    /// product a different tile colour each time the app started. That reads as
    /// a rendering bug, and worse, it makes a shelf look reshuffled when
    /// nothing has moved.
    ///
    /// Returns the index rather than the colour so the rule can be tested:
    /// comparing two SwiftUI `Color` values traps in a headless test process.
    nonisolated static func tintIndex(for seed: String) -> Int {
        let total = seed.unicodeScalars.reduce(0) { sum, scalar in
            (sum &+ Int(scalar.value)) % 100_003
        }
        return total % tints.count
    }
}
