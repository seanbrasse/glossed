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
public struct OnbPayoffView<Shelf: View>: View {
    @State private var model: PayoffModel
    /// Back to the quiz's last question. Nil hides the link — the debug
    /// catalog mounts this screen alone and has no quiz to return to.
    /// The example shelf, drawn by the app (it is `Shelf`'s bay view, and
    /// features never import features). `EmptyView` shows the words alone.
    private let exampleShelf: () -> Shelf
    private let onBack: (() -> Void)?
    private let onContinue: () -> Void

    public init(
        model: PayoffModel,
        @ViewBuilder exampleShelf: @escaping () -> Shelf,
        onBack: (() -> Void)? = nil,
        onContinue: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.exampleShelf = exampleShelf
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
    /// shelf"* — and then: *"make it an actual shelf like the one we build
    /// in app, with the shelf UI."* The neutral path used to be PRD §06·6's
    /// say-nothing fallback, a headline over 800pt of milk. Now it says
    /// what a shelf IS and shows one, drawn by the shelf's own bay view,
    /// which the app hands in (`OnboardingExampleShelf`).
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
        exampleShelf()
            .padding(.top, Tokens.Space.s3)
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

public extension OnbPayoffView where Shelf == EmptyView {
    /// The words alone — the debug catalog's mount, which has no app layer
    /// to draw a shelf.
    init(model: PayoffModel, onBack: (() -> Void)? = nil, onContinue: @escaping () -> Void) {
        self.init(model: model, exampleShelf: { EmptyView() }, onBack: onBack, onContinue: onContinue)
    }
}
