import DataKit
import DesignSystem
import SwiftUI

/// `G.Leaderboard` — the whole screen, in the frame's order: back, header +
/// butter badge, category pills, scope segments, the rows, the rule line.
///
/// The rules this screen carries (the map's caption is the first one):
///   · n on every row, and a row that can't be ranked yet says so instead
///     of hiding — rank renders "—" below min-n, never a number
///   · every claim names whose n it is (domain.md §5)
///   · the lowest board carries its reasons; the best board never does
///
/// Deferred, not decorated: the frame's scoped ConfidenceMeter has no
/// defined live data source, so it is absent rather than invented.
public struct LeaderboardView: View {
    @State private var model: LeaderboardModel
    private let onBack: (() -> Void)?
    private let onOpenProduct: ((CatalogHit) -> Void)?

    public init(
        model: LeaderboardModel,
        onBack: (() -> Void)? = nil,
        onOpenProduct: ((CatalogHit) -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.onBack = onBack
        self.onOpenProduct = onOpenProduct
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                if let onBack {
                    Button("← back", action: onBack)
                        .buttonStyle(.plain)
                        .font(Typography.mono(12))
                        .foregroundStyle(Tokens.Semantic.accentText)
                        .underline()
                }
                header
                categoryPills
                scopeRow
                boardBody
                Text(model.footerLine).meta()
            }
            // 110pt of bottom room: the floating nav sits over this screen.
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Ground.milk)
        .task { model.load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("leaderboard")
                .font(Typography.display(28))
                .tracking(-0.56)
                .foregroundStyle(Tokens.Ink.primary)
            Spacer(minLength: 0)
            Badge("ranked by face-off", tone: .butter)
        }
    }

    // MARK: - category pills

    private var categoryPills: some View {
        PillFlow(spacing: 6) {
            ForEach(model.categories) { category in
                pill(category, on: category.id == model.selectedCategoryID)
            }
        }
    }

    private func pill(_ category: DataKit.Category, on: Bool) -> some View {
        Button(category.label) { model.select(categoryID: category.id) }
            .buttonStyle(.plain)
            .font(Typography.mono(10.5))
            .kerning(0.6)
            .foregroundStyle(Tokens.Ink.primary)
            .padding(.vertical, 5)
            .padding(.horizontal, 11)
            .background(on ? Tokens.Cherry.soft : Tokens.Ground.card)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(
                on ? Tokens.Ink.primary : Tokens.Ground.line,
                lineWidth: on ? Tokens.Border.std : Tokens.Border.hair
            ))
            .animation(Tokens.Motion.pop(), value: on)
            .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: - scope + the lowest board

    private var scopeRow: some View {
        HStack(alignment: .center) {
            Segmented(
                options: [model.yoursOption, "everyone"],
                selection: Binding(
                    get: { model.scope == .yours ? model.yoursOption : "everyone" },
                    set: { model.scope = $0 == "everyone" ? .everyone : .yours }
                )
            )
            Spacer(minLength: 0)
            // The frame has no control for PRD §10's lowest board — a
            // deliberate gap, so this link is minimal on purpose and gets
            // workshopped in the PR rather than invented as chrome.
            Button(model.ascending ? "best first" : "lowest first") {
                model.ascending.toggle()
            }
            .buttonStyle(.plain)
            .font(Typography.mono(11))
            .foregroundStyle(Tokens.Semantic.accentText)
            .underline()
            .accessibilityLabel(model.ascending
                ? "switch to the best board" : "switch to the lowest board")
        }
    }

    // MARK: - the rows

    @ViewBuilder private var boardBody: some View {
        if model.isLoading {
            loadingRows
        } else if model.rows.isEmpty {
            // Empty is a legitimate answer, said in words — never a blank
            // scroll under a row of pills.
            Text("no face-offs in this category yet — boards build as people compare")
                .meta()
                .padding(.vertical, Tokens.Space.s4)
        } else {
            VStack(spacing: Tokens.Space.s2) {
                ForEach(model.rows) { row in
                    rowCard(row)
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func rowCard(_ row: LeaderboardRow) -> some View {
        let content = rowContent(row)
        // A row is a button only where a tap goes somewhere — an affordance
        // that leads nowhere is not offered (the full-page rule).
        if let onOpenProduct {
            Button {
                onOpenProduct(row.hit)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func rowContent(_ row: LeaderboardRow) -> some View {
        HStack(alignment: .center, spacing: Tokens.Space.s3) {
            rankSlot(row)
            ProductImage(
                catalog: model.imageURL(for: row.hit),
                kind: ProductMock.Kind.usual(forCategory: row.hit.categorySlug),
                tint: ProductMock.tint(for: row.hit.name),
                scale: 46
            )
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.hit.name)
                    .font(Typography.display(14.5, weight: 700))
                    .foregroundStyle(Tokens.Ink.primary)
                    .multilineTextAlignment(.leading)
                Text(row.hit.brandName).meta()
                evidence(row)
                if let reasons = row.dislikeReasons, !reasons.isEmpty {
                    // Only the lowest board carries these (0042), and they
                    // arrive thresholded — the reasons are the point there.
                    ChipGroup(reasons.map { Chip($0, kind: .dislike, size: .sm) })
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Tokens.Space.s3)
        .background(Tokens.Ground.card)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
        )
    }

    /// The caption's whole rule in one span: a number in cherry when the
    /// evidence carries it, "—" in faint ink when it does not — the row
    /// stays, the claim doesn't.
    private func rankSlot(_ row: LeaderboardRow) -> some View {
        let rank = model.rank(of: row)
        return Text(rank.map { "#\($0)" } ?? "—")
            .font(Typography.display(19))
            .foregroundStyle(rank == nil ? Tokens.Ink.faint : Tokens.Cherry.base)
            .frame(width: 26, alignment: .leading)
            .accessibilityLabel(rank.map { "ranked \($0)" } ?? "not ranked yet")
    }

    @ViewBuilder
    private func evidence(_ row: LeaderboardRow) -> some View {
        if row.isRankable {
            EvidenceLine(n: row.nUsers, label: model.evidenceLabel())
        } else {
            // Not routed through EvidenceLine's own empty heuristic (n < 5):
            // the gate here is the RPC's nulled percentile, and the words
            // quote the row's own threshold, whatever it is.
            Text(LeaderboardModel.emptyLine(n: row.nUsers, needed: row.needed)).meta()
        }
    }

    private var loadingRows: some View {
        VStack(spacing: Tokens.Space.s2) {
            ForEach(0 ..< 4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .fill(Tokens.Ground.card)
                    .frame(height: 66)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                            .strokeBorder(Tokens.Ground.line, lineWidth: Tokens.Border.hair)
                    )
            }
        }
        .accessibilityLabel("loading the board")
    }
}

/// The frame's wrapping pill row. DesignSystem's `FlowLayout` is internal to
/// its package and widening it is a DesignSystem PR of its own — this is the
/// same dozen lines, scoped here (the GLO-164 shape; noted in the PR).
private struct PillFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for (index, origin) in arrange(proposal: proposal, subviews: subviews).origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(cursor)
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, cursor.x - spacing)
        }
        return (CGSize(width: totalWidth, height: cursor.y + rowHeight), origins)
    }
}
