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
    private let onOpenProduct: ((CatalogHit) -> Void)?
    private let onOpenTrending: (() -> Void)?
    /// Renders an app-injected card by id (GLO-200). Nil for an id the app no
    /// longer recognises renders nothing — an affordance that leads nowhere is
    /// not offered, and a stale id must not become a blank card.
    private let injectedCard: ((String) -> AnyView?)?

    public init(
        model: DiscoverModel,
        onOpenProduct: ((CatalogHit) -> Void)? = nil,
        onOpenTrending: (() -> Void)? = nil,
        injectedCard: ((String) -> AnyView?)? = nil
    ) {
        _model = State(initialValue: model)
        self.onOpenProduct = onOpenProduct
        self.onOpenTrending = onOpenTrending
        self.injectedCard = injectedCard
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
                    stream
                }
            }
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Ground.milk)
        .task { model.load() }
    }

    // MARK: - the stream

    /// One scroll of mixed, self-labeling cards (GLO-195). No section
    /// headers: the header was labeling a shelf of cards, which is a
    /// catalog's shape — each card's basis line carries its own why.
    private var stream: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            ForEach(model.stream) { card in
                switch card {
                case let .pick(pick):
                    pickCard(pick)
                case let .crosswalk(rows):
                    crosswalkCard(rows)
                case .trendingTeaser:
                    // dropped when the app wires nothing — an affordance
                    // that leads nowhere is not offered (the full-page rule)
                    if let onOpenTrending {
                        trendingTeaser(onOpenTrending)
                    }
                case let .injected(id):
                    if let view = injectedCard?(id) {
                        view
                    }
                }
            }
        }
    }

    /// Trending as a card in the stream, not a header link. It navigates
    /// rather than claims, so it carries no n — the claims live on the
    /// other side of it, where every row shows its count (GLO-129).
    private func trendingTeaser(_ open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WHAT PEOPLE ARE LOGGING").eyebrow()
                    Text("trending, overall and in your skin type").meta()
                }
                Spacer(minLength: 0)
                Text("→")
                    .font(Typography.mono(13, bold: true))
                    .foregroundStyle(Tokens.Semantic.accentText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Space.s3)
            .background(Tokens.Ground.card)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("open trending")
    }

    private func pickCard(_ pick: DiscoverHit) -> some View {
        // The wander is the screen's one pop moment: the single loudest
        // card belongs to the row that claims the least.
        GlossedCard(
            tint: pick.basis == .exploration ? .butter : .plain,
            pop: pick.basis == .exploration
        ) {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                ProductCard(
                    meta: .init(
                        brand: pick.hit.brandName,
                        name: pick.hit.name,
                        variant: pick.hit.variantLabel
                    ),
                    onTap: {
                        model.tapped(pick)
                        onOpenProduct?(pick.hit)
                    },
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
        .contextMenu {
            if model.supportsDismissal, pick.basis != .exploration {
                // the wander is exempt: dismissing curiosity would teach
                // the engine from a row that never claimed to know you
                Button("not for me", role: .destructive) {
                    model.dismiss(pick, reason: "not_for_me")
                }
                Button("already own it") {
                    model.dismiss(pick, reason: "own_it")
                }
            }
        }
    }

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

    private func crosswalkCard(_ rows: [CrosswalkHit]) -> some View {
        GlossedCard(tint: .lilac) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                // never "your match" — people who wear what you wear
                Text("PEOPLE WHO WEAR WHAT YOU WEAR").eyebrow()
                ForEach(rows) { row in
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
        .onTapGesture {
            model.tappedCrosswalk(row)
            onOpenProduct?(row.hit)
        }
    }

    // MARK: - states

    private var loadingRows: some View {
        VStack(spacing: Tokens.Space.s3) {
            ForEach(0 ..< 3, id: \.self) { _ in
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
