import DesignSystem
import SwiftUI

/// The cold-start shelf. GLO-211, built to `G.Shelf`'s empty branch.
///
/// Every new account opens here, so the frame treats it as the product's
/// opening argument rather than a dead end: the shade cohort already knows
/// something, and these are the three things it agrees on. The frame writes
/// the rule into its own footer — *empty states are never blank*.
///
/// This is only `.nothingLogged`. The other four blank-shelf states are filter
/// dead-ends where one sentence naming the way out is right, and GLO-166's
/// reasoning for those still holds.
struct ShelfStageZeroView: View {
    let picks: [StageZeroPick]
    let isLoading: Bool
    let onAdd: (StageZeroPick) -> Void
    /// Opens the add-ladder. Named for the room it opens, not the rungs
    /// inside it — "scan or search" read as a search field to Sean.
    let onAddProduct: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            Text("NOTHING LOGGED YET · STAGE 0")
                .eyebrow(color: Tokens.Cherry.deep)
            Text("an empty shelf still knows your shade — start from these three")
                .handAside()
                .rotationEffect(Tokens.Rotate.r1)
                .fixedSize(horizontal: false, vertical: true)

            ConfidenceMeter(have: anchorsHeld, need: 5)

            picksSection

            // The shelf, with one tier and the invitation standing on it.
            // Sean, Sep 2: "Empty shelf should also show an empty shelf state
            // with a singular empty shelf" … "0 products should still be 1
            // tier and encourage users to add to their shelf" … "Put the
            // empty shelf under the empty shelf text between that and the
            // add a product button." So it sits here: after what the shade
            // cohort can say, right above the door.
            ShelfBayView.bare(onAdd: onAddProduct)

            HStack(spacing: Tokens.Space.s3) {
                Button("add a product", action: onAddProduct)
                    .buttonStyle(.glossed(.primary, block: true))
                Button("import a list", action: onImport)
                    .buttonStyle(.glossed(.secondary))
                    .fixedSize()
            }

            Text("your shade band, plus the products it agrees on.")
                .meta()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the shelf can honestly claim, rather than a number it would have
    /// to invent. It holds no anchor count — anchors come from fits on logged
    /// items and there are none — but a `.shade` pick is proof the server
    /// matched this person to an anchor cohort, so at least one exists.
    ///
    /// Nothing here fabricates the frame's `have={1}`: with no shade-based
    /// pick the meter reads 0 of 5, which is exactly what we can support.
    private var anchorsHeld: Int {
        picks.contains { $0.basis == .shade } ? 1 : 0
    }

    /// Three states, and the middle one is the reason this is not just a list.
    @ViewBuilder private var picksSection: some View {
        if isLoading {
            ProgressView().padding(.vertical, Tokens.Space.s4)
        } else if picks.isEmpty {
            // Nothing to recommend is not the same as nothing logged, and it
            // is reachable: a catalog with no products, or a cohort too small
            // to clear min-n. Saying so beats three empty rows — and beats
            // implying the shelf is broken when it is the evidence that is
            // missing.
            Text("no picks yet — there isn't enough logged in your shade to point at anything.")
                .meta()
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: Tokens.Space.s3) {
                ForEach(picks) { pick in
                    pickRow(pick)
                }
            }
        }
    }

    private func pickRow(_ pick: StageZeroPick) -> some View {
        GlossedCard {
            HStack(spacing: Tokens.Space.s3) {
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(pick.brand).meta()
                    Text(pick.name)
                        .font(Typography.display(Typography.Size.small, weight: 700))
                        .foregroundStyle(Tokens.Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    EvidenceLine(n: pick.n, label: pick.reason)
                }
                Spacer(minLength: Tokens.Space.s2)
                Button("add") { onAdd(pick) }
                    .buttonStyle(.glossed(.secondary, size: .sm))
                    .fixedSize()
            }
        }
    }
}
