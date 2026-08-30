import DesignSystem
import SwiftUI

/// The tune card — discover's door to `G.Tune`, injected by the app
/// through the stream's slot API. It NAVIGATES rather than claims, so it
/// carries no n (the trending teaser's rule): the claims live on the other
/// side, where every answer sharpens real ones.
public struct TuneCard: View {
    private let hasAnchor: Bool
    private let onOpen: () -> Void

    public init(hasAnchor: Bool, onOpen: @escaping () -> Void) {
        self.hasAnchor = hasAnchor
        self.onOpen = onOpen
    }

    /// The line names what's missing: a user with no anchor is told the
    /// one fact that most sharpens their matches comes from logging their
    /// foundation — never a re-quiz.
    public nonisolated static func line(hasAnchor: Bool) -> String {
        hasAnchor
            ? "skin type, concerns, the brands you rate — three taps"
            : "three taps — and logging your foundation sets your shade anchor"
    }

    public var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHARPEN YOUR MATCHES").eyebrow(color: Tokens.Semantic.accentText)
                    Text(Self.line(hasAnchor: hasAnchor)).meta()
                }
                Spacer(minLength: 0)
                Text("tune →")
                    .font(Typography.mono(11, bold: true))
                    .foregroundStyle(Tokens.Semantic.accentText)
                    .underline()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(Tokens.Support.butterSoft)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
        )
        .accessibilityLabel("sharpen your matches")
    }
}

/// The card's whole gate, pure so it is a fact in tests: the tune card is
/// offered to a signed-in user with a profile who either has no anchor
/// (GLO-18's acceptance line: never a re-quiz) or has never tuned.
public enum TuneGate {
    public static func shouldOffer(profileExists: Bool, hasAnchor: Bool, hasTuned: Bool) -> Bool {
        guard profileExists else { return false }
        return !hasAnchor || !hasTuned
    }
}
