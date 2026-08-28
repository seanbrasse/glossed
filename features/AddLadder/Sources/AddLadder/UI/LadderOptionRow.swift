import DesignSystem
import SwiftUI

/// One row of a rung's option list.
///
/// The ticket's first acceptance criterion — "none of these" carries the same
/// visual weight as a match — is met by construction rather than by matching
/// two styles by hand: this view takes no styling input, and the `switch`es
/// below decide only what the row *says*. Every case gets the same card, the
/// same border, the same minimum height, the same thumbnail slot and the same
/// chevron.
///
/// The thumbnail is on every row, "none of these" included. The near-match rung
/// tells people to check the photo rather than the name, which only works if
/// every option in the list is shaped like something with a photo.
public struct LadderOptionRow: View {
    private let option: LadderOption
    private let action: () -> Void

    public init(_ option: LadderOption, action: @escaping () -> Void) {
        self.option = option
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            GlossedCard(padding: Tokens.Space.s4) {
                HStack(spacing: Tokens.Space.s3) {
                    TypographicTile(brand: tileBrand, seed: tileSeed, size: 44)
                    VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        Text(title)
                            .font(.system(size: Typography.Size.body, weight: .semibold))
                            .foregroundStyle(Tokens.Ink.primary)
                            .multilineTextAlignment(.leading)
                        Text(subtitle).meta()
                    }
                    Spacer(minLength: Tokens.Space.s2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: Typography.Size.small, weight: .bold))
                        .foregroundStyle(Tokens.Ink.faint)
                }
                .frame(minHeight: Tokens.hitTarget)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    /// Until R2 is provisioned there is no catalog image to show, so every row
    /// renders the fallback tile — which is the floor of ADR 0004's chain and
    /// what a product with no photo is meant to look like anyway.
    private var tileBrand: String {
        switch option {
        case let .match(hit): hit.brandName
        case .noneOfThese: "" // renders "?"
        }
    }

    private var tileSeed: String {
        switch option {
        case let .match(hit): hit.categorySlug
        case let .noneOfThese(prompt): prompt
        }
    }

    private var title: String {
        switch option {
        case let .match(hit): hit.name.lowercased()
        case let .noneOfThese(prompt): prompt
        }
    }

    /// A personal product says so on the row rather than in a tooltip nobody
    /// opens — it is the user's own, and it is invisible to everyone else.
    private var subtitle: String {
        switch option {
        case let .match(hit):
            hit.scope == .personal
                ? "\(hit.brandName.lowercased()) · yours only"
                : "\(hit.brandName.lowercased()) · \(hit.categorySlug)"
        case .noneOfThese:
            "keep going — this never dead-ends"
        }
    }
}
