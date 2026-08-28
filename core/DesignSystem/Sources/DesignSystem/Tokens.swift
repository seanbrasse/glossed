import SwiftUI

/// The design tokens, ported 1:1 from the design kit's `tokens/*.css`.
/// These are the only source of color, spacing, radius, shadow, rotation,
/// and motion values in the app — no literals in views.
public enum Tokens {
    // MARK: - Ground & ink (rhode calm)

    public enum Ground {
        public static let milk = Color(hex: 0xEFEDE7) // app background (warm bone)
        public static let card = Color(hex: 0xFFFFFF) // raised surfaces
        public static let line = Color(hex: 0xDED9CF) // hairline rules on bone
        public static let lineOnCard = Color(hex: 0xE9E5DC)
    }

    public enum Ink {
        public static let primary = Color(hex: 0x1B1917)
        public static let soft = Color(hex: 0x5D5850)
        public static let faint = Color(hex: 0xA29C90)
    }

    // MARK: - Cherry (the one loud voice) + support hues (semantic only)

    public enum Cherry {
        public static let base = Color(hex: 0xE23A66)
        public static let deep = Color(hex: 0xA8123D)
        public static let soft = Color(hex: 0xF7DCE3)
    }

    public enum Support {
        public static let lilac = Color(hex: 0xA78BFA)
        public static let lilacSoft = Color(hex: 0xEAE6F6)
        public static let butter = Color(hex: 0xE9C64F)
        public static let butterSoft = Color(hex: 0xF3ECD9)
        public static let mint = Color(hex: 0x47946E)
        public static let mintSoft = Color(hex: 0xE0EBE2)
    }

    /// Chip polarity is sacred: like = mint, dislike = cherry, attribute = lilac.
    public enum Semantic {
        public static let like = Support.mint
        public static let likeSoft = Support.mintSoft
        public static let dislike = Cherry.base
        public static let dislikeSoft = Cherry.soft
        public static let attribute = Support.lilac
        public static let attributeSoft = Support.lilacSoft
        public static let accentText = Cherry.deep
    }

    // MARK: - Spacing, radius, hit targets

    public enum Space {
        public static let s1: CGFloat = 4
        public static let s2: CGFloat = 8
        public static let s3: CGFloat = 12
        public static let s4: CGFloat = 16
        public static let s5: CGFloat = 20
        public static let s6: CGFloat = 24
        public static let s8: CGFloat = 32
        public static let s10: CGFloat = 40
        public static let s12: CGFloat = 48
    }

    public enum Radius {
        public static let sm: CGFloat = 8 // inputs, small stickers
        public static let md: CGFloat = 12 // nested surfaces, thumbnails
        public static let lg: CGFloat = 18 // cards, sheets
        public static let pill: CGFloat = 999
    }

    public static let hitTarget: CGFloat = 44

    // MARK: - Borders & sticker shadows (hard offset, zero blur, always ink)

    public enum Border {
        public static let hair: CGFloat = 1.5 // resting surfaces, Ground.line
        public static let thin: CGFloat = 1.5 // chips + small controls, Ink.primary
        public static let std: CGFloat = 2 // buttons, hero cards, photos, Ink.primary
    }

    public enum Shadow {
        public static let sm: CGFloat = 1.5
        public static let md: CGFloat = 2
        public static let lg: CGFloat = 3
        public static let xl: CGFloat = 4
    }

    /// Sticker rotations — chips, hand notes, photos. Structural containers stay straight.
    public enum Rotate {
        public static let r1: Angle = .degrees(-2)
        public static let r2: Angle = .degrees(1.4)
        public static let r3: Angle = .degrees(-1)
        public static let r4: Angle = .degrees(2.2)
    }

    // MARK: - Motion (quick and springy; hover lifts, press flattens)

    public enum Motion {
        public static let fast: Double = 0.12
        public static let med: Double = 0.2
        public static func pop(_ duration: Double = fast) -> Animation {
            .timingCurve(0.2, 0.9, 0.3, 1.3, duration: duration)
        }
    }
}

extension Color {
    /// Token hex initializer. Not for use outside this package — add a token instead.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
