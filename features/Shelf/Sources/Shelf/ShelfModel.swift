import DataKit
import Foundation
import Observation

/// Shelf or list. Two readings of the same items, not a view and a fallback.
public enum ShelfViewMode: String, CaseIterable, Sendable {
    case shelf, list
}

/// The three ways the kit lets you reorder a bay.
///
/// `favorite` is the default and the only one that is about the product rather
/// than about you — it is the ranking, which is what the whole app is for.
public enum ShelfSort: String, CaseIterable, Sendable {
    case favorite, recent, brand
}

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
    public static let domains: [Domain] = [.makeup, .skincare, .haircare, .fragrance]

    public var selectedDomains: Set<Domain>
    public var sort: ShelfSort
    public var viewMode: ShelfViewMode
    /// Which category is expanded in the list view. One at a time, as the kit
    /// has it — an accordion where everything can be open is a long list with
    /// extra taps in it.
    public private(set) var openSection: String?

    private let sections: [ShelfSection]

    public init(
        sections: [ShelfSection],
        selectedDomains: Set<Domain> = [.makeup, .skincare],
        sort: ShelfSort = .favorite,
        viewMode: ShelfViewMode = .shelf,
        openSection: String? = nil
    ) {
        self.sections = sections
        self.selectedDomains = selectedDomains
        self.sort = sort
        self.viewMode = viewMode
        self.openSection = openSection
    }

    /// Tapping the open one closes it; tapping another moves the opening.
    public func toggleSection(_ slug: String) {
        openSection = openSection == slug ? nil : slug
    }

    /// The item whose sheet is open, if any.
    public private(set) var openItem: ShelfItem?

    public func open(_ item: ShelfItem) {
        openItem = item
    }

    public func closeSheet() {
        openItem = nil
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

    /// The sections currently on, in their given order, each internally sorted.
    public var shownSections: [ShelfSection] {
        sections
            .filter { selectedDomains.contains($0.domain) }
            .map { section in
                ShelfSection(
                    slug: section.slug,
                    label: section.label,
                    domain: section.domain,
                    items: ShelfModel.ordered(section.items, by: sort)
                )
            }
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

    /// Ordering within a bay.
    ///
    /// Every case is a total order with an explicit tiebreak, because SwiftUI
    /// re-sorts on every redraw and an unstable comparator makes a shelf shuffle
    /// itself while you look at it.
    ///
    /// `nonisolated` because it is arithmetic on an array and nothing about it
    /// belongs to the main actor — the same reason `TypographicTile.tintIndex`
    /// is. It also means the ordering rules can be tested without a `@MainActor`
    /// test, which is what they are: rules, not screen state.
    nonisolated static func ordered(_ items: [ShelfItem], by sort: ShelfSort) -> [ShelfItem] {
        switch sort {
        case .favorite: items.sorted(by: bestFirst)
        case .recent: items.sorted(by: newestFirst)
        case .brand: items.sorted(by: alphabeticalByBrand)
        }
    }

    /// Unranked items sort after ranked ones rather than at #0. A category
    /// below its unlock threshold has no order yet, and putting those first
    /// would read as "these are your favourites".
    private nonisolated static func bestFirst(_ lhs: ShelfItem, _ rhs: ShelfItem) -> Bool {
        knownFirst(lhs.rank, rhs.rank, tiebreak: lhs.name < rhs.name) { $0 < $1 }
    }

    /// Newest first, and an item with no date sorts last — the joined read that
    /// carries `created_at` does not exist yet (GLO-66), and a missing date
    /// guessed as "now" would park it at the top of the shelf as if it had just
    /// been logged.
    private nonisolated static func newestFirst(_ lhs: ShelfItem, _ rhs: ShelfItem) -> Bool {
        knownFirst(lhs.loggedAt, rhs.loggedAt, tiebreak: lhs.name < rhs.name) { $0 > $1 }
    }

    private nonisolated static func alphabeticalByBrand(_ lhs: ShelfItem, _ rhs: ShelfItem) -> Bool {
        switch lhs.brand.localizedCaseInsensitiveCompare(rhs.brand) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.name < rhs.name
        }
    }

    /// Two optionals ordered by `isBefore`, with anything unknown last and a
    /// stated tiebreak. Shared because "we do not know" must sort the same way
    /// for every column, or two sorts disagree about where the same item goes.
    private nonisolated static func knownFirst<T>(
        _ lhs: T?,
        _ rhs: T?,
        tiebreak: @autoclosure () -> Bool,
        isBefore: (T, T) -> Bool
    ) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?): isBefore(left, right) || (!isBefore(right, left) && tiebreak())
        case (nil, .some): false
        case (.some, nil): true
        case (nil, nil): tiebreak()
        }
    }
}
