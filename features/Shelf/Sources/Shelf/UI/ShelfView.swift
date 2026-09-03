import DataKit
import DesignSystem
import SwiftUI

/// TAB 2 · SHELF — the screen around the bays.
///
/// Built to `G.Shelf`: the heading and a count of what is on screen, the
/// four-domain filter on its own scrolling row bled to the screen edges, the
/// fragrance note when it applies, and the sort pills.
public struct ShelfView: View {
    @State var model: ShelfModel
    /// View-local on purpose: whether the field is showing is about this
    /// render of the screen; what is being searched for lives on the model.
    /// Closing clears the query — a hidden filter would be a shelf that
    /// silently lies about what you own.
    @State var isSearchOpen = false
    /// The cold-start picks (GLO-211). View-local: they are about this render
    /// of an empty shelf, not shelf state, and a shelf that fills stops
    /// needing them.
    @State var stageZeroPicks: [StageZeroPick] = []
    @State var stageZeroLoading = false
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    private let onTapItem: (ShelfItem) -> Void
    /// Absent in fixtures and previews, which is why it is optional: without
    /// it the cold-start screen still renders, saying it has no picks rather
    /// than pretending to load forever.
    let stageZero: ShelfStageZeroStore?
    /// The empty shelf's way in (GLO-108): opens the add-ladder, seeded with
    /// a pick's name or with nothing. Handed up because the ladder is a
    /// feature. Nil in fixtures — see `addProduct(_:)`.
    let onAddProduct: ((String) -> Void)?
    /// The item sheet's evidence, built by the app from the item (GLO-108).
    /// Nil in fixtures; withheld for a row with no variant, which has no
    /// page to draw from — the same fact `onOpenProduct` is withheld on.
    let productDetails: ((ShelfItem) -> AnyView)?
    /// Handed up to `app/`: a feature cannot import a feature, so the shelf
    /// reports the tap and the app owns the crossing (GLO-151).
    private let onOpenProduct: ((ShelfItem) -> Void)?
    /// Handed up for the same reason `onOpenProduct` is: the face-off lives in
    /// `features/Ranking` and a feature cannot import a feature.
    ///
    /// **Nil means the build cannot rank, and the sheet then offers no way to
    /// try.** It was previously not passed at all, so `ShelfItemSheet` fell
    /// back to its defaulted `{}` and the sheet's primary action — the kit's
    /// one pop moment on that surface — did nothing when tapped (GLO-240).
    private let onRank: ((ShelfItem) -> Void)?

    public init(
        model: ShelfModel,
        startsSearching: Bool = false,
        stageZero: ShelfStageZeroStore? = nil,
        onTapItem: @escaping (ShelfItem) -> Void = { _ in },
        onOpenProduct: ((ShelfItem) -> Void)? = nil,
        onRank: ((ShelfItem) -> Void)? = nil,
        onAddProduct: ((String) -> Void)? = nil,
        productDetails: ((ShelfItem) -> AnyView)? = nil
    ) {
        _model = State(initialValue: model)
        _isSearchOpen = State(initialValue: startsSearching)
        self.stageZero = stageZero
        self.onTapItem = onTapItem
        self.onOpenProduct = onOpenProduct
        self.onRank = onRank
        self.onAddProduct = onAddProduct
        self.productDetails = productDetails
    }

    public var body: some View {
        page
            .overlay {
                if let item = model.openItem {
                    ShelfItemSheet(
                        item: item,
                        rankedInCategory: model.rankedCount(inCategoryOf: item),
                        // Through the model: where it persists, and where a
                        // failed save falls back.
                        fit: Binding(
                            get: { model.openFit },
                            set: { model.fitChanged(to: $0) }
                        ),
                        onClose: model.closeSheet,
                        onRank: onRank.map { rank in { rank(item) } },
                        // No variant, no page to build (GLO-151).
                        onOpenProduct: onOpenProduct.flatMap { open in
                            item.variantID == nil ? nil : { open(item) }
                        },
                        details: productDetails.flatMap { build in
                            item.variantID == nil ? nil : build(item)
                        },
                        onRemove: model.supportsRemoval ? { model.removeOpenItem() } : nil,
                        isRemoving: model.isRemoving,
                        removeFailure: model.removeFailure?.userMessage,
                        chips: model.chips.supportsEditing ? model.chips : nil,
                        status: model.openStatus,
                        onStatusChange: model.supportsRemoval ? { model.statusChanged(to: $0) } : nil,
                        repurchase: model.openRepurchase,
                        onRepurchase: model.supportsRepurchase ? { model.repurchaseChanged(to: $0) } : nil
                    )
                }
            }
            .animation(Tokens.Motion.pop(Tokens.Motion.med), value: model.openItem)
    }

    /// The bay is a physical metaphor — things standing side by side, width
    /// being the point — so a shelf reflowed to one item per row has stopped
    /// being a shelf. Above an accessibility size it presents as the list
    /// instead (Sean, Aug 30, GLO-172).
    ///
    /// Derived, never written back: the user's stored toggle is a settings
    /// choice and this is a presentation decision, so they return to bays when
    /// they return to a normal text size.
    private var presentsAsList: Bool {
        model.viewMode == .list || dynamicTypeSize.isAccessibilitySize
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                heading
                // No chrome over an empty or one-item shelf: the controls
                // describe a list (`ShelfModel.showsControls`, Sean, Sep 2).
                if model.showsControls {
                    domainFilter
                    if model.showsFragranceNote {
                        Text("fragrance ranks by face-off only — no shade or skin axis, and we don't invent one")
                            .meta()
                    }
                    controls
                    if isSearchOpen {
                        searchField
                    }
                }
                emptySection
                if presentsAsList {
                    if dynamicTypeSize.isAccessibilitySize, model.viewMode == .shelf {
                        // The toggle still reads "bays" because the preference
                        // is untouched. Saying why beats looking broken.
                        Text("showing the list — the bays need more width than this text size leaves.")
                            .meta()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ShelfListView(
                        sections: model.shownSections,
                        openSection: model.openSection,
                        onToggleSection: model.toggleSection,
                        onTapItem: tapped
                    )
                } else {
                    ShelfBayView(sections: model.shownSections, onTap: tapped)
                }
            }
            // 110pt of bottom room: the floating nav sits over this screen.
            .padding(.init(top: 14, leading: 16, bottom: 110, trailing: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.Ground.milk)
    }

    /// The sheet is the shelf's own answer to a tap; `onTapItem` is for whatever
    /// contains the shelf and wants to know as well. Both fire, and neither
    /// swallows the other — a host that navigated away would otherwise leave a
    /// sheet open behind it.
    private func tapped(_ item: ShelfItem) {
        model.open(item)
        onTapItem(item)
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("your shelf")
                .font(Typography.display(30))
                .tracking(-0.6)
                .foregroundStyle(Tokens.Ink.primary)
                // Wrap rather than widen. display() scales since GLO-186, so
                // at accessibility sizes this title pushed the count badge off
                // the trailing edge and clipped the title's own first letters.
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            // Counts what is on screen. A total that ignored the filter would
            // contradict the shelf directly under it.
            Badge("\(model.shownItemCount) items", tone: .cherry)
        }
    }

    /// Its own row, 44 tall, scrolling horizontally and bled to the screen
    /// edges — four domains plus "all" do not fit on a narrow phone, and a
    /// control that stops at the page margin looks like it has been cut off
    /// rather than like it continues.
    private var domainFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Segmented(
                options: ShelfModel.domains.map(\.rawValue),
                selection: Binding(
                    get: { Set(model.selectedDomains.map(\.rawValue)) },
                    set: { model.selectedDomains = Set($0.compactMap(Domain.init(rawValue:))) }
                ),
                allowsAll: true,
                // Sean's Aug 29 ruling: the filter loses its outer container —
                // the row is already its own band, and a box inside a band
                // read as chrome on chrome. Stated kit divergence.
                chrome: .bare
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, -16)
    }

    var searchToggle: some View {
        Button {
            isSearchOpen.toggle()
            if !isSearchOpen {
                model.searchQuery = ""
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Tokens.Ink.primary)
                .frame(width: 34, height: 30)
                .background(isSearchOpen ? Tokens.Cherry.soft : Tokens.Ground.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSearchOpen ? Tokens.Ink.primary : Tokens.Ground.line,
                        lineWidth: isSearchOpen ? Tokens.Border.std : Tokens.Border.hair
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("find on your shelf")
        .accessibilityAddTraits(isSearchOpen ? [.isSelected] : [])
    }

    private var searchField: some View {
        GlossedInput(
            "find on your shelf",
            text: Binding(
                get: { model.searchQuery },
                set: { model.searchQuery = $0 }
            )
        )
        // A find field, not prose: "rhode" corrected to "Rhodes" is a shelf
        // that claims you own nothing. `GlossedInput` defaults to `.plain`
        // since GLO-57, so this needs no modifier — and cannot be forgotten.
    }

    /// Two 38×30 buttons inside one 2px ink pill, so it reads as a single
    /// control with two states rather than as two buttons that happen to touch.
    var viewToggle: some View {
        HStack(spacing: 0) {
            ForEach(ShelfViewMode.allCases, id: \.self) { mode in
                Button { model.viewMode = mode } label: {
                    Image(systemName: mode == .shelf ? "square.split.1x2" : "list.bullet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Tokens.Ink.primary)
                        .frame(width: 38, height: 30)
                        .background(model.viewMode == mode ? Tokens.Cherry.soft : Tokens.Ground.card)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.rawValue) view")
                .accessibilityAddTraits(model.viewMode == mode ? [.isSelected] : [])
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Ink.primary, lineWidth: Tokens.Border.std))
        .background(
            Capsule().fill(Tokens.Ink.primary)
                .offset(x: Tokens.Shadow.sm, y: Tokens.Shadow.sm)
        )
        .fixedSize()
    }
}
