import DesignSystem
import SwiftUI

/// `G.OnbHook` — the name, the promise, and one primary action. The floats
/// are the kit's six drawn products drifting behind the wordmark; the
/// login reveal swaps the footer in place so a returning user never leaves
/// the screen to find their way in.
public struct OnbHookView: View {
    private let onCreateAccount: () -> Void
    /// Returning-user doors. Nil hides the login reveal entirely — an
    /// affordance that leads nowhere is not offered (the full-page rule);
    /// they arrive with the account PR.
    private let onAppleLogin: (() -> Void)?
    private let onPhoneLogin: (() -> Void)?

    @State private var showLogin: Bool

    public init(
        onCreateAccount: @escaping () -> Void,
        onAppleLogin: (() -> Void)? = nil,
        onPhoneLogin: (() -> Void)? = nil,
        initialLogin: Bool = false
    ) {
        self.onCreateAccount = onCreateAccount
        self.onAppleLogin = onAppleLogin
        self.onPhoneLogin = onPhoneLogin
        _showLogin = State(initialValue: initialLogin)
    }

    private struct FloatSpec {
        let kind: ProductMock.Kind
        let tint: UInt32
        let height: CGFloat
        let rotation: Double
        let label: String
        let unit: UnitPoint
    }

    private static let floats: [FloatSpec] = [
        FloatSpec(
            kind: .compact,
            tint: 0xE2A1AC,
            height: 64,
            rotation: -11,
            label: "blush",
            unit: .init(x: 0.06, y: 0.06)
        ),
        FloatSpec(
            kind: .tube,
            tint: 0xD67287,
            height: 72,
            rotation: 9,
            label: "gloss",
            unit: .init(x: 0.94, y: 0.08)
        ),
        FloatSpec(
            kind: .mist,
            tint: 0xF2B8C6,
            height: 60,
            rotation: -6,
            label: "spf",
            unit: .init(x: 0.95, y: 0.5)
        ),
        FloatSpec(
            kind: .dropper,
            tint: 0xEDEAE3,
            height: 66,
            rotation: 7,
            label: "serum",
            unit: .init(x: 0.05, y: 0.48)
        ),
        FloatSpec(
            kind: .bottle,
            tint: 0xE9DCC9,
            height: 58,
            rotation: 14,
            label: "shampoo",
            unit: .init(x: 0.18, y: 0.94)
        ),
        FloatSpec(
            kind: .tube,
            tint: 0xC7A9D6,
            height: 58,
            rotation: -13,
            label: "balm",
            unit: .init(x: 0.82, y: 0.94)
        )
    ]

    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    ForEach(Array(Self.floats.enumerated()), id: \.offset) { _, float in
                        ProductMock(
                            kind: float.kind,
                            tint: Color(hexValue: float.tint),
                            scale: float.height,
                            rotation: .degrees(float.rotation),
                            label: float.label
                        )
                        .position(
                            x: proxy.size.width * float.unit.x,
                            y: proxy.size.height * float.unit.y
                        )
                    }
                    wordmark
                }
            }
            footer
        }
        .padding(.init(top: 10, leading: 20, bottom: 20, trailing: 20))
        .background(Tokens.Ground.milk)
    }

    private var wordmark: some View {
        VStack(spacing: Tokens.Space.s2) {
            (Text("glossed").foregroundStyle(Tokens.Ink.primary)
                + Text("*").foregroundStyle(Tokens.Cherry.base))
                .font(Typography.display(52))
                .tracking(-1.8)
            Text("your whole shelf, ranked ✿")
                .handAside()
                .rotationEffect(.degrees(-1.5))
        }
    }

    @ViewBuilder private var footer: some View {
        if showLogin, onAppleLogin != nil || onPhoneLogin != nil {
            loginReveal
        } else {
            VStack(spacing: Tokens.Space.s3) {
                Text("NO ADS · NO BOTS · NO STARS · NO GATEKEEPING").eyebrow()
                Button("create an account", action: onCreateAccount)
                    .buttonStyle(.glossed(block: true))
                if onAppleLogin != nil || onPhoneLogin != nil {
                    Button("or have an account? log in →") { showLogin = true }
                        .buttonStyle(.plain)
                        .font(Typography.mono())
                        .foregroundStyle(Tokens.Semantic.accentText)
                        .underline()
                }
            }
        }
    }

    private var loginReveal: some View {
        VStack(spacing: Tokens.Space.s3) {
            Text("WELCOME BACK · SAME TWO WAYS IN").eyebrow()
            if let onAppleLogin {
                Button {
                    onAppleLogin()
                } label: {
                    Label("log in with apple", systemImage: "apple.logo")
                }
                .buttonStyle(.glossed(block: true))
            }
            if let onPhoneLogin {
                Button {
                    onPhoneLogin()
                } label: {
                    Label("log in with phone number", systemImage: "phone")
                }
                .buttonStyle(.glossed(.secondary, block: true))
            }
            Button("← I\u{2019}m new here") { showLogin = false }
                .buttonStyle(.plain)
                .font(Typography.mono())
                .foregroundStyle(Tokens.Ink.soft)
                .underline()
        }
    }
}

extension Color {
    /// Kit float tints — screen-local hues from the frame, not tokens; the
    /// drawn products are illustration, not chrome.
    init(hexValue: UInt32) {
        self.init(
            .sRGB,
            red: Double((hexValue >> 16) & 0xFF) / 255,
            green: Double((hexValue >> 8) & 0xFF) / 255,
            blue: Double(hexValue & 0xFF) / 255,
            opacity: 1
        )
    }
}
