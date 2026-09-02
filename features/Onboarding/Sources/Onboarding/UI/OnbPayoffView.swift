import DataKit
import DesignSystem
import SwiftUI

/// `G.OnbPayoff` — the moment before signup earns the signup, or stays
/// quiet. Backed: the exact-shade claim with its numbers and their
/// provenance. Neutral: no claim, no counts, and nothing that reads as one.
///
/// Deferred from the frame, not decorated: the ConfidenceMeter (its fixture
/// numbers match no RPC quantity — the leaderboard's ruling at this screen)
/// and the three recommendation rows (no rec source exists before an
/// account; `discover_for_user` resolves auth.uid). The claim IS the payoff
/// until those have real data behind them.
public struct OnbPayoffView: View {
    @State private var model: PayoffModel
    /// Back to the quiz's last question. Nil hides the link — the debug
    /// catalog mounts this screen alone and has no quiz to return to.
    private let onBack: (() -> Void)?
    private let onContinue: () -> Void

    public init(model: PayoffModel, onBack: (() -> Void)? = nil, onContinue: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onBack = onBack
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    if let onBack {
                        // The same link the account screen carries, so the
                        // three screens between the hook and the account
                        // write all back up the same way.
                        Button("← back", action: onBack)
                            .buttonStyle(.textLink)
                    }
                    switch model.phase {
                    case .loading:
                        loadingBlock
                    case let .backed(evidence):
                        backedBlock(evidence)
                    case .neutral:
                        neutralBlock
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(.init(top: 18, leading: 22, bottom: 22, trailing: 22))
        .background(Tokens.Ground.milk)
        .task { model.load() }
    }

    @ViewBuilder
    private func backedBlock(_ evidence: PayoffEvidence) -> some View {
        Text("BEFORE YOU EVEN SIGN UP").eyebrow(color: Tokens.Semantic.accentText)
        Text(PayoffModel.headline(exactShadeCount: evidence.exactShadeCount))
            .font(Typography.display(31))
            .tracking(-0.62)
            .foregroundStyle(Tokens.Ink.primary)
            .padding(.top, 12)
        if let anchor = model.anchor {
            Badge(PayoffModel.anchorBadge(anchor), tone: .mint)
        }
        EvidenceLine(n: evidence.withFitCount, label: PayoffModel.evidenceLabel, tone: .ink)
            .padding(.top, Tokens.Space.s2)
    }

    /// Sean, Sep 2: *"I also don't get what this screen is for … show an
    /// example shelf full of popular products and be like build your
    /// shelf."* The neutral path used to be PRD §06·6's say-nothing
    /// fallback — a headline and a sentence about matches that do not exist
    /// yet, over 800pt of milk. Now it says what a shelf IS and shows one:
    /// six products, each with its n when the leaderboard supplied it, or
    /// labelled as an example when the catalog stood in. The claim rule
    /// holds either way — see `PayoffModel.shelfEyebrow`.
    @ViewBuilder
    private var neutralBlock: some View {
        Text("YOUR SHELF, NEXT").eyebrow()
        Text("build your\nshelf")
            .font(Typography.display(31))
            .tracking(-0.62)
            .foregroundStyle(Tokens.Ink.primary)
            .padding(.top, 12)
        Text("every product you own, ranked by which one you actually reach for")
            .handAside()
            .rotationEffect(.degrees(-1))
        if !model.shelf.isEmpty {
            exampleShelf
                .padding(.top, Tokens.Space.s3)
        }
    }

    /// Three across, two down — the shelf's own bay, at a glance.
    private var exampleShelf: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(PayoffModel.shelfEyebrow(isRanked: model.shelfIsRanked)).eyebrow()
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s2), count: 3),
                spacing: Tokens.Space.s3
            ) {
                ForEach(model.shelf) { pick in
                    shelfTile(pick)
                }
            }
        }
        .animation(.easeOut(duration: Tokens.Motion.med), value: model.shelf)
    }

    private func shelfTile(_ pick: PayoffModel.ShelfPick) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ProductImage(
                        catalog: pick.imageURL,
                        kind: ProductMock.Kind.usual(forCategory: pick.categorySlug),
                        tint: Tokens.Cherry.soft,
                        scale: 0.7
                    )
                }
                .background(Tokens.Ground.card)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.md)
                        .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
                )
            Text(pick.brand).meta().lineLimit(1)
            Text(pick.name)
                .font(Typography.display(Typography.Size.small, weight: 700))
                .foregroundStyle(Tokens.Ink.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let line = PayoffModel.shelfLine(pick) {
                Text(line).meta()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var loadingBlock: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            ForEach(0 ..< 2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .fill(Tokens.Ground.card)
                    .frame(height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                            .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
                    )
            }
        }
        .accessibilityLabel("checking who wears your shade")
    }

    private var footer: some View {
        VStack(spacing: Tokens.Space.s2) {
            // "create your account", not "save my shelf" (Sean, Sep 2): the
            // door says what is behind it.
            Button("create your account", action: onContinue)
                .buttonStyle(.glossed(block: true))
            if case .backed = model.phase, let anchor = model.anchor {
                Text(PayoffModel.footerLine(anchor))
                    .meta()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Tokens.Space.s3)
    }
}
