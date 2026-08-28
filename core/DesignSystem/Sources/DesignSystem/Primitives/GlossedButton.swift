import SwiftUI

/// Pop-layer button: pill, 2px ink border, hard sticker shadow, press flattens
/// into the shadow (design sheet §05).
public struct GlossedButtonStyle: ButtonStyle {
    public enum Variant {
        case primary // cherry fill, white text
        case secondary // card fill, ink text
        case ink // ink fill, white text (sign in with apple)
        case mint // mint-soft fill, ink text

        var fill: Color {
            switch self {
            case .primary: Tokens.Cherry.base
            case .secondary: Tokens.Ground.card
            case .ink: Tokens.Ink.primary
            case .mint: Tokens.Support.mintSoft
            }
        }

        var foreground: Color {
            switch self {
            case .primary, .ink: .white
            case .secondary, .mint: Tokens.Ink.primary
            }
        }
    }

    public enum Size {
        case sm, md, lg

        var vertical: CGFloat {
            switch self {
            case .sm: 7
            case .md: 10
            case .lg: 14
            }
        }

        var font: CGFloat {
            switch self {
            case .sm: 13
            case .md: 15
            case .lg: 16
            }
        }
    }

    let variant: Variant
    let size: Size
    let block: Bool

    /// The kit's own disabled recipe (`components/glossed-lib.js` Button):
    /// the whole sticker fades to 45% and stops answering presses — shadow
    /// and border stay, so it still reads as the same object, just inert.
    /// GLO-76: without this a disabled button was pixel-identical to an
    /// enabled one.
    @Environment(\.isEnabled) private var isEnabled

    public init(_ variant: Variant = .primary, size: Size = .md, block: Bool = false) {
        self.variant = variant
        self.size = size
        self.block = block
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        let shadow = pressed ? 0 : Tokens.Shadow.lg
        configuration.label
            .font(.system(size: size.font, weight: .bold))
            .padding(.vertical, size.vertical)
            .padding(.horizontal, Tokens.Space.s5)
            .frame(maxWidth: block ? .infinity : nil, minHeight: size == .sm ? 0 : Tokens.hitTarget)
            .background(variant.fill)
            .foregroundStyle(variant.foreground)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
            .background(
                Capsule()
                    .fill(Tokens.Ink.primary)
                    .offset(x: shadow, y: shadow)
            )
            .offset(x: pressed ? Tokens.Shadow.lg : 0, y: pressed ? Tokens.Shadow.lg : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Tokens.Motion.pop(), value: pressed)
    }
}

public extension ButtonStyle where Self == GlossedButtonStyle {
    static func glossed(
        _ variant: GlossedButtonStyle.Variant = .primary,
        size: GlossedButtonStyle.Size = .md,
        block: Bool = false
    ) -> GlossedButtonStyle {
        GlossedButtonStyle(variant, size: size, block: block)
    }
}
