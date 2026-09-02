import DataKit
import DesignSystem
import SwiftUI

/// `G.Product` — the whole screen, in the kit's order: back, hero, evidence
/// card, fit block, actions.
///
/// The page has no stars and no score. Rank is a position in a bucket and says
/// of-what; every claim carries its n or is not made.
public struct ProductPageView: View {
    @State private var model: ProductPageModel
    private let onBack: () -> Void
    private let onRank: () -> Void
    private let onLeaderboard: () -> Void

    public init(
        model: ProductPageModel,
        onBack: @escaping () -> Void = {},
        onRank: @escaping () -> Void = {},
        onLeaderboard: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.onBack = onBack
        self.onRank = onRank
        self.onLeaderboard = onLeaderboard
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button("← back", action: onBack)
                    .buttonStyle(.plain)
                    .font(Typography.mono(12))
                    .foregroundStyle(Tokens.Semantic.accentText)
                    .underline()
                hero
                // The evidence and the fit answer, shared with the sheets that
                // show a product before or beside its page (GLO-108).
                ProductDetailsView(model: model)
                actions
            }
            // 110pt of bottom room: the floating nav sits over this screen.
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Ground.milk)
    }

    /// The object is the biggest thing on the page and it is tilted — this is
    /// the one screen that is about a single product rather than a list of them.
    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            // The catalog image, with the drawn mock underneath it as the
            // chain's floor (GLO-153). `ProductImage` already owns that
            // fallback — the page simply never handed it a URL, so every
            // product rendered as a generic silhouette while the shelf, one
            // tap away, showed the real thing.
            ProductImage(
                catalog: model.product.catalogImageURL,
                kind: model.product.packaging,
                tint: ProductMock.tint(for: model.product.name),
                scale: 124,
                rotation: .degrees(-4),
                label: model.product.brand
            )
            .frame(width: 124)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.eyebrow).eyebrow()
                Text(model.product.name)
                    .font(Typography.display(30))
                    .tracking(-0.6)
                    .lineSpacing(-1.5)
                    .foregroundStyle(Tokens.Ink.primary)
                    .padding(.vertical, 4)
                if let subtitle = model.subtitle {
                    Text(subtitle).meta()
                }
                if model.showsRank, let rank = model.product.rank, let outOf = model.product.rankedInCategory {
                    RankBadge(rank: rank, outOf: outOf, categoryLabel: model.product.categoryLabel)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The receipts. Mint because it is the page's good news, and the one place
    /// a count about other people appears.
    private var actions: some View {
        HStack(spacing: 10) {
            if model.canRank {
                Button("rank it", action: onRank)
                    .buttonStyle(.glossed(block: true))
                    .frame(maxWidth: .infinity)
                Button("leaderboard", action: onLeaderboard)
                    .buttonStyle(.glossed(.secondary))
                    .fixedSize()
            } else {
                Button("leaderboard", action: onLeaderboard)
                    .buttonStyle(.glossed(.secondary, block: true))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
