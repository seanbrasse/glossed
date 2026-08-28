import CoreText
import SwiftUI

/// Four voices (design sheet §03): display = Bricolage Grotesque 700–800, huge and
/// lowercase; body = system sans; hand = Caveat, rare and always rotated; mono =
/// Space Mono for meta, counts, and eyebrows (the only uppercase).
public enum Typography {
    /// Registers the bundled OFL fonts. Call once at app start (SPM packages
    /// can't declare UIAppFonts, so registration is at runtime).
    public static func registerFonts() {
        let files = [
            "BricolageGrotesque", "Caveat",
            "SpaceMono-Regular", "SpaceMono-Bold", "SpaceMono-Italic"
        ]
        for file in files {
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts")
            else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: - Scale (design sheet §03 table)

    public enum Size {
        public static let hero: CGFloat = 64 // wordmark, product hero (52–104 in the kit)
        public static let h1: CGFloat = 40
        public static let h2: CGFloat = 26
        public static let h3: CGFloat = 17
        public static let body: CGFloat = 16
        public static let small: CGFloat = 14
        public static let hand: CGFloat = 22
        public static let meta: CGFloat = 11.5
        public static let eyebrow: CGFloat = 11
        public static let tag: CGFloat = 10.5
    }

    /// Display: Bricolage Grotesque, variable weight (default 800), tight tracking.
    public static func display(_ size: CGFloat, weight: CGFloat = 800) -> Font {
        variableFont("Bricolage Grotesque", size: size, weight: weight, relativeTo: relative(size))
    }

    /// Hand: Caveat 700 — one aside per screen, always rotated, cherry-deep.
    public static func hand(_ size: CGFloat = Size.hand) -> Font {
        variableFont("Caveat", size: size, weight: 700, relativeTo: .title3)
    }

    /// Mono: Space Mono — meta, counts, eyebrows.
    public static func mono(_ size: CGFloat = Size.meta, bold: Bool = false) -> Font {
        .custom(bold ? "Space Mono Bold" : "Space Mono", size: size, relativeTo: .caption)
    }

    private static func relative(_ size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<18: .body
        case ..<28: .title3
        case ..<44: .title
        default: .largeTitle
        }
    }

    private static func variableFont(
        _ family: String, size: CGFloat, weight: CGFloat, relativeTo style: Font.TextStyle
    ) -> Font {
        #if canImport(UIKit)
            let weightAxis = 0x7767_6874 // 'wght'
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: family,
                kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [weightAxis: weight]
            ])
            return Font(UIFont(descriptor: descriptor, size: size))
        #else
            return .custom(family, size: size, relativeTo: style)
        #endif
    }
}

// MARK: - Text style helpers

public extension Text {
    /// Eyebrow: mono, uppercase, .18em tracking — the only uppercase in the app.
    func eyebrow(color: Color = Tokens.Ink.soft) -> some View {
        font(Typography.mono(Typography.Size.eyebrow))
            .textCase(.uppercase)
            .kerning(Typography.Size.eyebrow * 0.18)
            .foregroundStyle(color)
    }

    /// Meta: mono lowercase — timestamps, counts, categories.
    func meta(color: Color = Tokens.Ink.soft) -> some View {
        font(Typography.mono())
            .kerning(Typography.Size.meta * 0.04)
            .foregroundStyle(color)
    }

    /// Handwritten aside — rotated by the caller with a Tokens.Rotate angle.
    func handAside(color: Color = Tokens.Cherry.deep) -> some View {
        font(Typography.hand())
            .foregroundStyle(color)
    }
}
