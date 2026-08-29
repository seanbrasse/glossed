import DataKit
import DesignSystem
import SwiftUI

/// Tab 1 (GLO-20): picked for you, the crosswalk card, and the labeled
/// wander. Built from the design system in the kit's voice — G.Discover is
/// the frame family; per the standing ruling the screen is workshopped in
/// the PR rather than traced from a frame.
///
/// The rules this screen carries:
///   · every claim shows its n via EvidenceLine, and names whose n it is
///   · the wander is labeled a wander — it never wears evidence
///   · the crosswalk says "also wear", NEVER "your match" (PRD §05)
///   · empty is never blank — the screen explains how picks get made
public struct DiscoverView: View {
    @State private var model: DiscoverModel
    private let onOpenProduct: ((UUID) -> Void)?

    public init(model: DiscoverModel, onOpenProduct: ((UUID) -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onOpenProduct = onOpenProduct
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                Text("discover")
                    .font(Typography.display(30))
                    .foregroundStyle(Tokens.Ink.primary)

                switch model.phase {
                case .loading:
                    loadingRows
                case .empty:
                    emptyState
                case .loaded:
                    if !model.picks.isEmpty {
                        picksSection
                    }
                    if !model.crosswalk.isEmpty {
                        crosswalkCard
                    }
                }
            }
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Ground.milk)
        .task { model.load() }
    }

    // MARK: - picks

    private var picksSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text("PICKED FOR YOU").eyebrow()
            ForEach(model.picks) { pick in
                pickCard(pick)
            }
        }
    }

    @ViewBuilder
    private func pickCard(_ pick: DiscoverHit) -> some View {
        // The wander is the screen's one pop moment: the single loudest
        // card belongs to the row that claims the least.
        GlossedCard(tint: pick.basis == .exploration ? .butter : .plain,
                    pop: pick.basis == .exploration) {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                ProductCard(
                    meta: .init(
                        brand: pick.hit.brandName,
                        name: pick.hit.name,
                        variant: pick.hit.variantLabel
                    ),
                    onTap: { onOpenProduct?(pick.hit.id) },
                    thumb: {
                        ProductImage(
                            catalog: model.imageURL(for: pick.hit),
                            kind: ProductMock.Kind.usual(forCategory: pick.hit.categorySlug),
                            tint: Tokens.Support.lilacSoft,
                            scale: 0.8
                        )
                    }
                )
                basisLine(pick)
            }
        }
    }

    @ViewBuilder
    private func basisLine(_ pick: DiscoverHit) -> some View {
        HStack(spacing: Tokens.Space.s2) {
            Text(DiscoverModel.basisLine(pick.basis)).meta(color: Tokens.Ink.primary)
            if let label = DiscoverModel.evidenceLabel(pick.basis) {
                EvidenceLine(n: pick.basisN, label: label)
            } else {
                // exploration: no n, no claim — the words say why it is here
                Text("no evidence, just curiosity").meta()
            }
        }
    }

    // MARK: - crosswalk

    private var crosswalkCard: some View {
        GlossedCard(tint: .lilac) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                // never "your match" — people who wear what you wear
                Text("PEOPLE WHO WEAR WHAT YOU WEAR").eyebrow()
                ForEach(model.crosswalk) { row in
                    crosswalkRow(row)
                }
            }
        }
    }

    @ViewBuilder
    private func crosswalkRow(_ row: CrosswalkHit) -> some View {
        let title = "also wear " + row.hit.name
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.display(15, weight: 700))
                    .foregroundStyle(Tokens.Ink.primary)
                    .multilineTextAlignment(.leading)
                Text(row.hit.brandName).meta()
            }
            Spacer(minLength: 0)
            EvidenceLine(n: row.n, label: "wear both")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onOpenProduct?(row.hit.id) }
    }

    // MARK: - states

    private var loadingRows: some View {
        VStack(spacing: Tokens.Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .fill(Tokens.Ground.card)
                    .frame(height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                            .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
                    )
            }
        }
        .accessibilityLabel("loading your picks")
    }

    /// Never blank (the kit's own caption for stage 0): the screen explains
    /// where picks come from instead of showing an apology.
    private var emptyState: some View {
        GlossedCard(tint: .mint) {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("NOTHING PICKED YET").eyebrow()
                Text("your picks build from what you log")
                    .font(Typography.display(17))
                    .foregroundStyle(Tokens.Ink.primary)
                Text("rate a few products on your shelf — likes, chips,"
                     + " a ranking — and this page starts earning its name")
                .meta()
            }
        }
    }
}
