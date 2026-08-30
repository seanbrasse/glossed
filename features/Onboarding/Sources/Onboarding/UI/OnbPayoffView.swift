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
    private let onContinue: () -> Void

    public init(model: PayoffModel, onContinue: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
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

    /// PRD §06·6's fallback: swatches-and-say-nothing. No counts, no
    /// "match", nothing that reads as a claim — the words explain what will
    /// exist, not what does. (Copy is not in the kit — workshop candidate.)
    @ViewBuilder
    private var neutralBlock: some View {
        Text("YOUR SHELF, NEXT").eyebrow()
        Text("let\u{2019}s get your\nshelf built")
            .font(Typography.display(31))
            .tracking(-0.62)
            .foregroundStyle(Tokens.Ink.primary)
            .padding(.top, 12)
        Text("as people with your exact products log how they fit, your matches show up here — with the receipts")
            .meta()
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
            Button("save my shelf", action: onContinue)
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
