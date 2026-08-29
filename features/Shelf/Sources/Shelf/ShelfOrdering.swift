import Foundation

// The bay-ordering rules, out of `ShelfModel.swift` for the file-length
// ceiling — nonisolated static rules, not screen state, so they split
// cleanly and stay testable without a @MainActor test.

extension ShelfModel {
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
