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
    @State private var fit: FitAnswer?
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
                evidenceCard
                if model.product.isAnchor {
                    fitBlock
                }
                actions
            }
            // 110pt of bottom room: the floating nav sits over this screen.
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Ground.milk)
        .task { await model.load() }
    }

    /// The object is the biggest thing on the page and it is tilted — this is
    /// the one screen that is about a single product rather than a list of them.
    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            ProductMock(
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
    private var evidenceCard: some View {
        GlossedCard(tint: .mint, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                shadeClaim
                // The frame puts a scattered `ChipGroup` here — attribute and
                // experience chips with their counts, a dislike sitting in the
                // same group as the likes. Nothing reads aggregate chips yet, so
                // the group is absent rather than invented: a chip with no count
                // behind it is exactly the claim this card exists to make
                // impossible. GLO-68.
            }
        }
    }

    @ViewBuilder
    private var shadeClaim: some View {
        switch model.shadeClaim {
        case let .backed(n):
            EvidenceLine(n: n, label: "people in your shade rated it", tone: .ink)
        case .notEnoughYet:
            // Incompleteness as a promise, not an apology (PRD §06). It says
            // what will change it, which "not enough data" does not.
            Text("not enough reports in your shade yet — this fills in as people log theirs").meta()
        case .unavailable:
            // Never "not enough yet": we did not ask, so we know nothing.
            Text(model.failure?.userMessage ?? "couldn't check the reports just now").meta()
        }
    }

    /// Its own pop card, because answering it is the one thing this page wants
    /// from you — fit is captured at log time, not rating time (PRD §05), and
    /// this is the second chance to give it.
    private var fitBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            FitControl(selection: $fit)
            Divider()
                .overlay(Tokens.Ground.line)
                .padding(.top, 12)
            ConfidenceMeter(have: anchorsHeld, need: 5)
                .padding(.top, 10)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        )
        .background(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.md, y: Tokens.Shadow.md)
        )
    }

    /// The meter moves the moment you answer, which is the payoff for
    /// answering — the kit is explicit that it must not wait for a reload.
    ///
    /// The baseline is `withFitCount` from the same RPC that supplies the n
    /// above, so the two halves of this page agree about the same user. Nothing
    /// persists the answer yet: the write exists (`ShelfRepository.captureFit`)
    /// but it needs a `user_item_id`, and this page is opened from a variant.
    /// GLO-47's second half carries that.
    private var anchorsHeld: Int {
        (model.anchorsWithFit ?? 0) + (fit == nil ? 0 : 1)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("rank it", action: onRank)
                .buttonStyle(.glossed(block: true))
                .frame(maxWidth: .infinity)
            Button("leaderboard", action: onLeaderboard)
                .buttonStyle(.glossed(.secondary))
                .fixedSize()
        }
    }
}
