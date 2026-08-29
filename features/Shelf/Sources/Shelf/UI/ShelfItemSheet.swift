import DataKit
import DesignSystem
import SwiftUI

/// One item, opened from either view — the `sheet` branch of `G.Shelf`.
///
/// A sheet rather than a push, which is the app's habit and not an accident:
/// the shelf stays visible behind it, so the thing you are reading about is
/// still in the row you tapped. Coming back is a dismissal, not a navigation.
public struct ShelfItemSheet: View {
    private let item: ShelfItem
    /// How many products in this category carry a rank. The badge is `#2 of 5`
    /// and both halves have to come from the same place, or a shelf says you
    /// are second of five while showing you three things.
    private let rankedInCategory: Int
    private let onClose: () -> Void
    private let onRank: () -> Void
    private let onOpenProduct: () -> Void
    /// How many people wear this exact shade — the anchor section's evidence
    /// line. Nil omits the line: an absent aggregate is not a claim of zero,
    /// and nothing reads `agg_variant_stats` for the sheet yet (GLO-63 family).
    private let exactShadeCount: Int?
    /// Owned outside, because the answer is not the sheet's: it is loaded
    /// before the sheet exists and persists after it closes. A sheet holding
    /// its own copy could never show a read that resolves after it opens.
    @Binding private var fit: Set<FitAnswer>
    /// Nil hides the lifecycle row entirely — fixture states with no store
    /// must not offer a remove that writes nowhere (GLO-72).
    private let onRemove: (() -> Void)?
    private let isRemoving: Bool
    /// The failed remove's user message, owned by the model like the fit's
    /// answers are — a failure outlives any one render of this sheet.
    private let removeFailure: String?
    /// Nil hides the chips + note section — fixture states with no chips
    /// model must not offer edits that write nowhere (GLO-16).
    private let chips: ShelfChipsModel?
    /// The live status (the model's optimistic copy) and its change handler —
    /// nil handler hides the icons and detail, the no-fake-writes rule again
    /// (GLO-72 → GLO-87).
    private let status: ItemStatus?
    private let onStatusChange: ((ItemStatus) -> Void)?

    public init(
        item: ShelfItem,
        rankedInCategory: Int,
        fit: Binding<Set<FitAnswer>> = .constant([]),
        exactShadeCount: Int? = nil,
        onClose: @escaping () -> Void,
        onRank: @escaping () -> Void = {},
        onOpenProduct: @escaping () -> Void = {},
        onRemove: (() -> Void)? = nil,
        isRemoving: Bool = false,
        removeFailure: String? = nil,
        chips: ShelfChipsModel? = nil,
        status: ItemStatus? = nil,
        onStatusChange: ((ItemStatus) -> Void)? = nil
    ) {
        self.item = item
        self.rankedInCategory = rankedInCategory
        _fit = fit
        self.exactShadeCount = exactShadeCount
        self.onClose = onClose
        self.onRank = onRank
        self.onOpenProduct = onOpenProduct
        self.onRemove = onRemove
        self.isRemoving = isRemoving
        self.removeFailure = removeFailure
        self.chips = chips
        self.status = status
        self.onStatusChange = onStatusChange
    }

    /// The status the sheet renders everywhere: the optimistic pick the
    /// moment it is tapped, the row's truth otherwise.
    private var liveStatus: ItemStatus {
        status ?? item.status
    }

    /// Fit is asked only of an anchor category that has actually been worn
    /// (GLO-145). A want-to-try has no wear to report, so its answer is not
    /// shade evidence — and the section's own line promises we only match
    /// shades people have actually worn, which the ungated version stood
    /// directly on top of and contradicted. The predicate is GLO-87's, the
    /// same one the chips and status detail gate on; `liveStatus` and not
    /// `item.status` so the section leaves the moment the bookmark is
    /// tapped, rather than after the write settles.
    var showsFit: Bool {
        item.isAnchorCategory && liveStatus.isTried
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            scrim
            sheet
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
    }

    /// Tapping outside closes. The kit's scrim is `rgba(27,25,23,.45)` — ink at
    /// 45%, not black, so the page underneath stays warm rather than going grey.
    private var scrim: some View {
        Button(action: onClose) {
            Rectangle()
                .fill(Tokens.Ink.primary.opacity(0.45))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close")
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            grabber
            header
            if let benefit = item.benefitLine {
                Text(benefit)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(Tokens.Ink.primary)
                    .padding(.top, 12)
            }
            if showsFit {
                fitSection
            }
            // Chips render only for tried items (GLO-87): a want-to-try has
            // no experience to chip, and offering the editor would invite
            // reviews of products never opened.
            if let chips, liveStatus.isTried {
                ShelfChipsSection(model: chips)
            }
            actions
            if let onStatusChange, liveStatus.isTried {
                ShelfTriedDetail(status: liveStatus, onChange: onStatusChange)
            }
            if let onRemove {
                ShelfRemoveRow(isRemoving: isRemoving, failure: removeFailure, onRemove: onRemove)
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
        // The sheet's background runs to the very bottom of the screen, but its
        // buttons must not: without this the primary action sits under the home
        // indicator, which eats the bottom of its tap target.
        .safeAreaPadding(.bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Ground.card)
        .clipShape(.rect(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std)
        }
        // The sticker shadow points *up* here — the sheet is rising off the
        // page rather than resting on it.
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Tokens.Ink.primary)
                .offset(y: -3)
        )
        .transition(.move(edge: .bottom))
    }

    private var grabber: some View {
        Capsule()
            .fill(Tokens.Ground.line)
            .frame(width: 44, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            // Bigger than anywhere else and tilted: this is the one screen
            // where the object itself is the subject rather than a thumbnail.
            ProductImage(
                catalog: item.catalogImageURL,
                kind: item.packaging,
                tint: ProductMock.tint(for: item.name),
                scale: 82,
                rotation: .degrees(-3),
                label: item.brand
            )
            // The slot is as wide as the drawing scale, not as wide as the
            // drawing. A brand sticker is wider than the bottle it is stuck to
            // — that is what a label looks like — and without a reserved slot
            // it runs under the product name and makes the title unreadable.
            // Very long brands still overflow; capping the sticker itself
            // belongs in `ProductMock`, not here.
            .frame(width: 82)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.brand).eyebrow()
                Text(item.name)
                    .font(Typography.display(21))
                    .tracking(-0.42)
                    .foregroundStyle(Tokens.Ink.primary)
                    .padding(.top, 3)
                    .padding(.bottom, 2)
                Text(statusLine).meta()
                badges
                // The two icons on the product (GLO-87): saved / tried,
                // right where the object is the subject.
                if let onStatusChange {
                    ShelfTriedIcons(status: liveStatus, onChange: onStatusChange)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            closeButton
        }
    }

    /// "joy · 7.5ml · week 3", and just the status when there is no variant —
    /// never a stray separator standing in for a size we do not have (GLO-63).
    private var statusLine: String {
        // The optimistic status wins, so the header agrees with the icons
        // the moment one is tapped (salvaged from #157).
        let label = (status != nil && status != item.status)
            ? ShelfItem.label(for: liveStatus) : item.statusLabel()
        return [item.variant, label]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private var badges: some View {
        HStack(spacing: 6) {
            // Rank is always relative and always says of-what. A bare "#2" is
            // the star rating this product does not have.
            if let rank = item.rank, rankedInCategory > 0 {
                Badge("#\(rank) of \(rankedInCategory)", tone: .cherry)
            }
            if item.isPersonalScope {
                Badge("yours only", tone: .lilac)
            }
        }
        .padding(.top, 7)
    }

    /// The frame's anchor section: the fit control above an evidence line,
    /// behind a hairline. Only for anchor categories — shade is only evidence
    /// where a shade is meant to match skin. One stated divergence: the kit
    /// draws FitControl at a small size here; the port has one size, and
    /// inventing a second is a DesignSystem PR, not a sheet detail.
    private var fitSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            FitControl(selection: $fit)
            if let exactShadeCount {
                EvidenceLine(n: exactShadeCount, label: "people wear this exact shade")
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Tokens.Ground.line).frame(height: 1.5)
        }
        .padding(.top, 14)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Text("×")
                .font(Typography.mono(16))
                .foregroundStyle(Tokens.Ink.soft)
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("close")
    }

    /// "rank it" is the primary action on every item, which is the product's
    /// whole argument: a shelf is only worth having if it is ordered.
    private var actions: some View {
        HStack(spacing: 10) {
            Button("rank it", action: onRank)
                .buttonStyle(.glossed(block: true))
                .frame(maxWidth: .infinity)
            Button("full page", action: onOpenProduct)
                .buttonStyle(.glossed(.secondary))
                .fixedSize()
        }
        .padding(.top, 16)
    }
}
