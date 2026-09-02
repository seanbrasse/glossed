import DataKit
import DesignSystem
import SwiftUI

/// One item, opened from either view — the `sheet` branch of `G.Shelf`.
///
/// A sheet rather than a push, which is the app's habit and not an accident:
/// the shelf stays visible behind it, so the thing you are reading about is
/// still in the row you tapped. Coming back is a dismissal, not a navigation.
public struct ShelfItemSheet: View {
    let item: ShelfItem
    /// How many products in this category carry a rank. The badge is `#2 of 5`
    /// and both halves have to come from the same place, or a shelf says you
    /// are second of five while showing you three things.
    let rankedInCategory: Int
    private let onClose: () -> Void
    /// Nil means this build cannot rank, and then the button is not drawn.
    ///
    /// **It used to default to `{}`**, and `ShelfView` never passed one, so
    /// the sheet's primary action — the kit's one pop moment on this
    /// surface — was a no-op on every item in the app (GLO-240). A control
    /// that does nothing is worse than one that is not offered; this file
    /// already applies that rule to `onRemove`, `onStatusChange` and
    /// `onRepurchase`, and `rank it` was the exception.
    private let onRank: (() -> Void)?
    /// Nil hides "full page" entirely (GLO-151). The button shipped wired to
    /// an empty default and `ShelfView` never passed anything, so it sat on
    /// the sheet doing nothing — an affordance that lies about what the app
    /// can do, which is GLO-72's no-fake-writes rule pointed at navigation.
    /// Optional now, like `onRemove` and `onStatusChange`, so a caller that
    /// cannot open the page cannot accidentally offer it.
    private let onOpenProduct: (() -> Void)?
    /// The product's own evidence, shown in place below the actions behind a
    /// `swipe up for more` hint — Sean, Sep 2: *"this is what the full page
    /// button should be replaced with (tell the user to swipe up for more
    /// details)"*. Handed in by the app: the view that draws it belongs to
    /// another feature. When present, the `full page` button is not offered.
    private let details: AnyView?
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
    let status: ItemStatus?
    let onStatusChange: ((ItemStatus) -> Void)?
    /// "Would you buy it again?" — the saved answer and its handler (GLO-87).
    private let repurchase: RepurchaseAnswer?
    private let onRepurchase: ((RepurchaseAnswer?) -> Void)?

    public init(
        item: ShelfItem,
        rankedInCategory: Int,
        fit: Binding<Set<FitAnswer>> = .constant([]),
        exactShadeCount: Int? = nil,
        onClose: @escaping () -> Void,
        onRank: (() -> Void)? = nil,
        onOpenProduct: (() -> Void)? = nil,
        details: AnyView? = nil,
        onRemove: (() -> Void)? = nil,
        isRemoving: Bool = false,
        removeFailure: String? = nil,
        chips: ShelfChipsModel? = nil,
        status: ItemStatus? = nil,
        onStatusChange: ((ItemStatus) -> Void)? = nil,
        repurchase: RepurchaseAnswer? = nil,
        onRepurchase: ((RepurchaseAnswer?) -> Void)? = nil
    ) {
        self.item = item
        self.rankedInCategory = rankedInCategory
        _fit = fit
        self.exactShadeCount = exactShadeCount
        self.onClose = onClose
        self.onRank = onRank
        self.onOpenProduct = onOpenProduct
        self.details = details
        self.onRemove = onRemove
        self.isRemoving = isRemoving
        self.removeFailure = removeFailure
        self.chips = chips
        self.status = status
        self.onStatusChange = onStatusChange
        self.repurchase = repurchase
        self.onRepurchase = onRepurchase
    }

    /// What the sheet's content measured on the last layout pass (GLO-160).
    /// Zero until the first measurement lands.
    @State private var contentHeight: CGFloat = 0

    /// The status the sheet renders everywhere: the optimistic pick the
    /// moment it is tapped, the row's truth otherwise.
    var liveStatus: ItemStatus {
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

    /// Whether "full page" is offered at all (GLO-151). Named so a test can
    /// fail on it: the bug this replaces was a button wired to an empty
    /// default, which no test could see and no screenshot could show.
    var showsFullPage: Bool {
        onOpenProduct != nil && details == nil
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                scrim
                boundedSheet(available: geo.size.height - ShelfSheetHeight.topGap)
            }
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

    /// The sheet, held to the screen (GLO-160).
    ///
    /// Scrolls only when it has to: `resolved` hands back the content's own
    /// height whenever that fits, so a sheet that fits today is laid out
    /// exactly as it is today. The card is drawn behind the *content* rather
    /// than behind the scroll view, which is what keeps a short sheet a short
    /// card resting on the bottom edge instead of a full-height panel.
    private func boundedSheet(available: CGFloat) -> some View {
        ScrollView {
            sheet
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ShelfSheetHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .frame(height: ShelfSheetHeight.resolved(content: contentHeight, available: available))
        .onPreferenceChange(ShelfSheetHeightKey.self) { contentHeight = $0 }
        .scrollBounceBehavior(.basedOnSize)
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
            if let details {
                moreSection(details)
            }
            if let onStatusChange, liveStatus.isTried {
                ShelfTriedDetail(
                    status: liveStatus,
                    onChange: onStatusChange,
                    repurchase: repurchase,
                    onRepurchase: onRepurchase
                )
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

    var closeButton: some View {
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

    /// The evidence the page would show, here instead — the sheet already
    /// scrolls (GLO-160), so the door is a hint, not a button.
    private func moreSection(_ details: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("swipe up for more ↑").meta()
            details
        }
        .padding(.top, 16)
    }

    /// "rank it" is the primary action on every item, which is the product's
    /// whole argument: a shelf is only worth having if it is ordered.
    private var actions: some View {
        HStack(spacing: 10) {
            if let onRank {
                Button("rank it", action: onRank)
                    .buttonStyle(.glossed(block: true))
                    .frame(maxWidth: .infinity)
            }
            if showsFullPage, let onOpenProduct {
                Button("full page", action: onOpenProduct)
                    // Alone in the row it takes the whole width rather than
                    // sitting half-width beside a gap — the same rule
                    // `ProductPageView.actions` follows when `rank it` is
                    // absent there.
                    .buttonStyle(.glossed(onRank == nil ? .primary : .secondary, block: onRank == nil))
                    .frame(maxWidth: onRank == nil ? .infinity : nil)
                    .fixedSize(horizontal: onRank != nil, vertical: false)
            }
        }
        .padding(.top, 16)
    }
}
