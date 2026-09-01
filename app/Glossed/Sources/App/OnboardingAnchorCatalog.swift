import DesignSystem
import SwiftUI

// The anchor question's brands, products and shades.

/// **This is the kit's own foundation data (`G.OnbQuiz`), not a live catalog
/// read, and that is a fact about the CATALOG rather than a shortcut here.**
/// `variants.shade_hex` is populated for **4 rows out of 9,019** (counted, Aug
/// 31), so a live read would draw a picker with four coloured swatches and
/// nine thousand blanks. `ShadeAnchorPicker.Shade.hex` is non-optional, so the
/// alternative is inventing a colour for every shade in the catalog — which is
/// the one thing this app does not do with data it does not have.
///
/// So the shapes here are real published shades from four real foundation
/// lines, and `AppSession.resolveAnchorVariant` maps a chosen one back to a
/// REAL `variants.id` when the local catalog carries it — the anchor the user
/// picks is a live row even though the swatch beside it came from the kit.
///
/// The ingest gap is [GLO-269]. When `shade_hex` is populated this file becomes
/// a query and nothing else moves.
enum OnboardingAnchorCatalog {
    private static func swatch(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    /// The kit's own foundation fixture (`G.OnbQuiz`), so the anchor step
    /// renders the picker in the shape the frame shows. The live catalog
    /// read arrives with the account PR's wiring.
    static let entries: [ShadeAnchorPicker.BrandEntry] = [
        .init(brand: "fenty beauty", products: [
            .init(name: "pro filt'r soft matte", shades: [
                .init(code: "220", hex: swatch(0xE0B891), tone: 5, n: 31),
                .init(code: "240", hex: swatch(0xD9A87E), tone: 6, n: 12),
                .init(code: "290", hex: swatch(0xC08B5E), tone: 7, n: 24),
                .init(code: "330", hex: swatch(0x8C5E3C), tone: 9, n: 9)
            ])
        ]),
        .init(brand: "rare beauty", products: [
            .init(name: "liquid touch weightless", shades: [
                .init(code: "21n", hex: swatch(0xE8C4A0), tone: 4, n: 6),
                .init(code: "23w", hex: swatch(0xDCA97F), tone: 6, n: 7),
                .init(code: "26w", hex: swatch(0xCC9668), tone: 7, n: 11),
                .init(code: "31c", hex: swatch(0xA87A54), tone: 8, n: 5)
            ])
        ]),
        .init(brand: "nars", products: [
            .init(name: "light reflecting foundation", shades: [
                .init(code: "mont blanc", hex: swatch(0xEBD3B8), tone: 3, n: 8),
                .init(code: "punjab", hex: swatch(0xCFA37C), tone: 6, n: 5),
                .init(code: "barcelona", hex: swatch(0xA87A54), tone: 8, n: 14)
            ]),
            .init(name: "soft matte concealer", shades: [
                .init(code: "custard", hex: swatch(0xE7C49C), tone: 4, n: 6),
                .init(code: "ginger", hex: swatch(0xD6A67C), tone: 6, n: 4)
            ])
        ]),
        .init(brand: "estée lauder", products: [
            .init(name: "double wear", shades: [
                .init(code: "2c2", hex: swatch(0xE6C6A4), tone: 4, n: 9),
                .init(code: "3w1", hex: swatch(0xD8AA7C), tone: 6, n: 17),
                .init(code: "4n1", hex: swatch(0xBD8B5E), tone: 7, n: 7)
            ])
        ])
    ]
}
