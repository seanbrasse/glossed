import DataKit
import DesignSystem
import SwiftUI

/// What is known about a product, below its name: the shade cohort's
/// evidence and, when this is an anchor you own, the fit answer and the
/// confidence meter. The product page's middle, split out so the sheets
/// that open a product — the add-ladder's shade pick, the shelf's item
/// sheet — can show the same facts in place instead of sending the person
/// to a full page (Sean, Sep 2: *"we should also be able to scroll the
/// popup when adding a product up to see more details on it"*).
///
/// What is NOT here, and why: aggregate chips ("commonly selected user
/// chips") have no read in the frozen core yet (GLO-68 / GLO-227), and a
/// chip with no count behind it is exactly the claim this card exists to
/// make impossible; there is no product description column. Both stay
/// absent rather than invented.
public struct ProductDetailsView: View {
    /// State, not a plain property: a host that builds this view inside a
    /// closure hands in a new model on every render, and the one that
    /// loaded would never be the one on screen. `State(initialValue:)` keeps
    /// the first model for the view's identity, so a host resets it with
    /// `.id(...)` when the product changes.
    @State private var model: ProductPageModel

    public init(model: ProductPageModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            evidenceCard
            // Anchor *and* answerable (GLO-165): the control shows only when
            // a shelf row is there to write to — see `canCaptureFit`.
            if model.product.isAnchor, model.canCaptureFit {
                fitBlock
            }
        }
        .task {
            // Shade evidence is an anchor's question; asking it about a
            // fragrance would only ever come back empty.
            guard model.product.isAnchor else { return }
            // The saved answer is read alongside the evidence, not after it:
            // the meter's baseline and the control's state are two halves of
            // the same claim about the same user (GLO-47). Loaded here, not
            // by the page, so a sheet that shows only this still loads.
            model.loadFit()
            await model.load()
        }
    }

    private var evidenceCard: some View {
        GlossedCard(tint: .mint, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if !model.product.isAnchor {
                    // Shade is evidence only where a shade is meant to match
                    // skin. Everything else ranks by face-off, and we say so
                    // rather than print a cohort line that cannot apply.
                    Text("no shade axis for \(model.product.categoryLabel) — this one ranks by face-off")
                        .meta()
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.isLoading {
                    Text("checking the reports…").meta()
                } else {
                    shadeClaim
                }
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
            FitControl(
                selection: Binding(
                    get: { model.fit },
                    set: { model.fitChanged(to: $0) }
                )
            )
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
    /// above, so the two halves of this page agree about the same user.
    ///
    /// The answer persists now (GLO-47's second half). It used to go nowhere,
    /// and the reason given here was that the write "needs a `user_item_id`,
    /// and this page is opened from a variant" — true when it was written and
    /// false since #213, which made the page reachable from the shelf, where
    /// the row's id *is* the `user_item_id`.
    private var anchorsHeld: Int {
        (model.anchorsWithFit ?? 0) + (model.fit.isEmpty ? 0 : 1)
    }

    // The frame's two buttons — and only the ones that lead somewhere.
    //
    // `rank it` places this product among the ones you already have, so a page
    // reached without owning it has nothing to place (GLO-241). The board does
    // not need you to own anything, so it is always here, and takes the whole
    // row when it is alone rather than sitting half-width beside a gap.
}
