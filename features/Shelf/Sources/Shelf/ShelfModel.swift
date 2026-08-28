import DataKit
import DesignSystem
import Foundation
import Observation

/// What the shelf screen shows: which domains are on, how the bays are ordered,
/// and the bays that fall out of those two answers.
///
/// No transport. The sections are handed in, because nothing in the frozen core
/// can supply them yet (GLO-66) — and keeping the shape of "sections in, bays
/// out" means the filtering and ordering are testable today rather than after
/// the read lands.
@MainActor
@Observable
public final class ShelfModel {
    /// Every domain, in the kit's order. Not `Domain.allCases`: the enum's order
    /// is a schema detail and this one is a design decision — makeup first
    /// because it is the most-logged, fragrance last because it is the newest.
    /// `nonisolated`: it is an immutable list, and the section grouping — plain
    /// arithmetic off the main actor — orders by it.
    public nonisolated static let domains: [Domain] = [.makeup, .skincare, .haircare, .fragrance]

    public var selectedDomains: Set<Domain>
    public var sort: ShelfSort
    public var viewMode: ShelfViewMode
    /// Find-what-I-own (GLO-73). Filters live over brand, name, variant and
    /// the bay label; empty means no filter. It queries the shelf, never the
    /// catalog — finding a product to *add* is the ladder's job.
    public var searchQuery = ""
    /// Which category is expanded in the list view. One at a time, as the kit
    /// has it — an accordion where everything can be open is a long list with
    /// extra taps in it.
    public private(set) var openSection: String?

    private let sections: [ShelfSection]
    private let fitStore: ShelfFitStore?
    private let lifecycle: ShelfLifecycleStore?
    /// Fired after a lifecycle write lands — the host re-reads the shelf, the
    /// same contract the ladder's `onShelfChanged` already has.
    private let onShelfChanged: (() -> Void)?

    public init(
        sections: [ShelfSection],
        selectedDomains: Set<Domain> = [.makeup, .skincare],
        sort: ShelfSort = .favorite,
        viewMode: ShelfViewMode = .shelf,
        openSection: String? = nil,
        fitStore: ShelfFitStore? = nil,
        lifecycle: ShelfLifecycleStore? = nil,
        onShelfChanged: (() -> Void)? = nil
    ) {
        self.sections = sections
        self.selectedDomains = selectedDomains
        self.sort = sort
        self.viewMode = viewMode
        self.openSection = openSection
        self.fitStore = fitStore
        self.lifecycle = lifecycle
        self.onShelfChanged = onShelfChanged
    }

    /// Tapping the open one closes it; tapping another moves the opening.
    public func toggleSection(_ slug: String) {
        openSection = openSection == slug ? nil : slug
    }

    /// The item whose sheet is open, if any.
    public private(set) var openItem: ShelfItem?

    /// The open item's fit answers, as the sheet's control shows them.
    ///
    /// Loaded when an anchor item opens, written through `fitChanged(to:)`.
    /// Empty while the load is in flight — an unanswered control, which is
    /// what the truth is until the read says otherwise.
    public private(set) var openFit: Set<FitAnswer> = []

    /// The last set the store confirmed. A failed save falls back here, so the
    /// control never keeps showing an answer that did not persist.
    private var persistedFit: Set<FitAnswer> = []

    /// Whether the user has touched the control since the sheet opened. A load
    /// that resolves after an edit loses: the newer fact wins.
    private var fitEdited = false

    /// Internal, not private: tests await these to order the async work.
    var fitLoadTask: Task<Void, Never>?
    var fitSaveTask: Task<Void, Never>?

    public func open(_ item: ShelfItem) {
        openItem = item
        openFit = []
        persistedFit = []
        fitEdited = false
        isRemoving = false
        removeFailure = nil
        fitLoadTask?.cancel()
        guard item.isAnchorCategory, let fitStore else { return }
        fitLoadTask = Task { [id = item.id] in
            guard let saved = try? await fitStore.load(id) else { return }
            // Late answers do not overwrite: a different sheet, or an edit made
            // while the read was in flight, is newer than what was read.
            guard !Task.isCancelled, openItem?.id == id, !fitEdited else { return }
            openFit = saved
            persistedFit = saved
        }
    }

    public func closeSheet() {
        openItem = nil
        fitLoadTask?.cancel()
    }

    // MARK: - Lifecycle (GLO-72)

    /// Whether removal is wired at all. The sheet hides the row when it is
    /// not — a remove that writes nowhere must not be offered (fixture
    /// states run with no store).
    public var supportsRemoval: Bool {
        lifecycle != nil
    }

    /// A removal in flight. The sheet disables the action while true — a
    /// second tap during the write would be a second update, harmless but
    /// dishonest about what one tap did.
    public private(set) var isRemoving = false
    /// The last removal that failed, held for the sheet to say so. Cleared on
    /// open and on retry.
    public private(set) var removeFailure: GlossedError?

    /// Internal, not private: tests await it to order the async work.
    var removeTask: Task<Void, Never>?

    /// Removes the open item from the shelf — a soft delete; the schema keeps
    /// the row, the app stops showing it. On success the sheet closes and the
    /// host re-reads, so the item leaves bays, list and counts in one motion.
    /// On failure the sheet stays up and says why: a remove that silently
    /// did not happen is an item that reappears on the next launch.
    public func removeOpenItem() {
        guard let item = openItem, let lifecycle, !isRemoving else { return }
        isRemoving = true
        removeFailure = nil
        removeTask = Task { [id = item.id] in
            defer { isRemoving = false }
            do throws(GlossedError) {
                try await lifecycle.remove(id)
                guard openItem?.id == id else { return }
                closeSheet()
                onShelfChanged?()
            } catch {
                // A different sheet is a different conversation — a stale
                // failure must not land on whatever opened since.
                guard openItem?.id == id else { return }
                removeFailure = error
            }
        }
    }

    /// The sheet's control writes here. Optimistic: the control shows the new
    /// answer immediately, the save runs behind it, and a failure reverts to
    /// the last persisted set rather than leaving a lie on screen.
    ///
    /// Saves are chained in order — `capture_fit` replaces the whole set, so
    /// two saves racing out of order could persist the older answer last.
    public func fitChanged(to answers: Set<FitAnswer>) {
        guard let item = openItem, item.isAnchorCategory else { return }
        openFit = answers
        fitEdited = true
        guard let fitStore else { return }
        fitSaveTask = Task { [previous = fitSaveTask, id = item.id] in
            await previous?.value
            do {
                try await fitStore.save(id, answers)
                guard openItem?.id == id else { return }
                persistedFit = answers
            } catch {
                // Only the latest edit reverts — an older save failing under a
                // newer pending one says nothing about what ends up persisted.
                guard openItem?.id == id, openFit == answers else { return }
                openFit = persistedFit
            }
        }
    }

    /// The denominator of "#2 of 5".
    ///
    /// Counts the *ranked* products in the category, not everything in it. A
    /// category with five products where two have been compared is "#1 of 2" —
    /// "of 5" would claim a comparison against three things nobody has looked
    /// at, which is the same overstatement as a star rating.
    ///
    /// Counted across the whole category rather than the filtered view: turning
    /// off a domain does not change where a product placed.
    public func rankedCount(inCategoryOf item: ShelfItem) -> Int {
        sections
            .first { $0.slug == item.categorySlug }?
            .items.count { $0.rank != nil } ?? 0
    }

    /// The sections currently on, in their given order, each internally
    /// sorted, holding only what matches the search. A bay with no matches
    /// drops out whole — an empty bay would read as an empty shelf.
    public var shownSections: [ShelfSection] {
        sections
            .filter { selectedDomains.contains($0.domain) }
            .map { section in
                ShelfSection(
                    slug: section.slug,
                    label: section.label,
                    domain: section.domain,
                    items: ShelfModel.ordered(
                        section.items.filter { $0.matches(searchQuery) },
                        by: sort
                    )
                )
            }
            .filter { !$0.items.isEmpty }
    }

    /// A real query found nothing. Distinct from "every domain off": the empty
    /// state has to say the search came up dry, not show a bare shelf.
    public var searchCameUpEmpty: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty && shownSections.isEmpty
    }

    /// The bays, for a shelf of the given inside width.
    ///
    /// A function rather than a property because packing depends on how much
    /// shelf there is, and only the view knows that. Nothing about which items
    /// are shown or in what order depends on the width — that is all decided by
    /// `shownSections`, which stays testable without a layout.
    public func bays(fittingWidth width: CGFloat) -> [ShelfBay] {
        ShelfBay.bays(from: shownSections, fittingWidth: width)
    }

    /// Counts what is on screen, not what is owned. A count that ignored the
    /// filter would contradict the shelf under it.
    public var shownItemCount: Int {
        shownSections.reduce(0) { $0 + $1.items.count }
    }

    /// Fragrance has no shade axis and no skin axis, so it is ranked by face-off
    /// alone. The kit says that out loud whenever fragrance is on rather than
    /// letting someone wonder why one domain behaves differently.
    public var showsFragranceNote: Bool {
        selectedDomains.contains(.fragrance)
    }

    public func toggle(_ domain: Domain) {
        if selectedDomains.contains(domain) {
            selectedDomains.remove(domain)
        } else {
            selectedDomains.insert(domain)
        }
    }
}
