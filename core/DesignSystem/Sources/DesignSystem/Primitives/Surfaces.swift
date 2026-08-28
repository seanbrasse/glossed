import SwiftUI

/// Resting-layer card: hairline border, no shadow, no rotation. The calm half
/// of the system — most of a screen is made of these.
public struct GlossedCard<Content: View>: View {
    public enum Tint {
        case plain, mint, lilac, butter, cherry

        var fill: Color {
            switch self {
            case .plain: Tokens.Ground.card
            case .mint: Tokens.Support.mintSoft
            case .lilac: Tokens.Support.lilacSoft
            case .butter: Tokens.Support.butterSoft
            case .cherry: Tokens.Cherry.soft
            }
        }
    }

    let tint: Tint
    /// The one pop moment a screen is allowed. Two shouting cards read as none.
    let pop: Bool
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    public init(
        tint: Tint = .plain,
        pop: Bool = false,
        padding: CGFloat = Tokens.Space.s4,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tint = tint
        self.pop = pop
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.fill)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(
                        pop ? Tokens.Ink.primary : Tokens.Ground.line,
                        lineWidth: pop ? Tokens.Border.std : Tokens.Border.hair
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .fill(pop ? Tokens.Ink.primary : .clear)
                    .offset(x: Tokens.Shadow.md, y: Tokens.Shadow.md)
            )
    }
}

/// Circular icon button, 44pt so it clears the tap-target floor.
public struct IconButton: View {
    let systemName: String
    let label: String
    let pop: Bool
    let action: () -> Void

    public init(_ systemName: String, label: String, pop: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.pop = pop
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.Ink.primary)
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                .background(Tokens.Ground.card)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        pop ? Tokens.Ink.primary : Tokens.Ground.line,
                        lineWidth: pop ? Tokens.Border.thin : Tokens.Border.hair
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Toast. The `hand` variant carries the app's editorial voice — rotated,
/// cherry-deep, used for moments worth a reaction ("ranked! nice taste ✿").
public struct Toast: View {
    let message: String
    let hand: Bool

    public init(_ message: String, hand: Bool = false) {
        self.message = message
        self.hand = hand
    }

    public var body: some View {
        Group {
            if hand {
                Text(message)
                    .handAside()
                    .rotationEffect(Tokens.Rotate.r3)
            } else {
                Text(message)
                    .font(.system(size: Typography.Size.small, weight: .semibold))
                    .foregroundStyle(Tokens.Ink.primary)
            }
        }
        .padding(.vertical, Tokens.Space.s3)
        .padding(.horizontal, Tokens.Space.s5)
        .background(Tokens.Ground.card)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.thin))
        .background(
            Capsule().fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.md, y: Tokens.Shadow.md)
        )
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Bottom sheet. Used for the + drawer and every item detail — the app prefers
/// sheets to pushes so context stays visible behind them.
public struct GlossedSheet<Content: View>: View {
    @ViewBuilder let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Tokens.Ground.line)
                .frame(width: 44, height: 4)
                .padding(.top, Tokens.Space.s3)
                .padding(.bottom, Tokens.Space.s3)
                .accessibilityHidden(true)
            content()
                .padding(.horizontal, Tokens.Space.s5)
                .padding(.bottom, Tokens.Space.s6)
        }
        .frame(maxWidth: .infinity)
        .background(Tokens.Ground.card)
        .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        }
    }
}
