import Foundation
import Observation

// "starting a tag opens up a search bar" (GLO-266).
//
// **The scope is not decided, so it is not baked in.** Sean's own words:
// "a search bar of your shelf (or maybe all of our items? Maybe the whole
// catalog but your shelf and categories first? Not sure)". The whole of that
// question reduces to ONE injected closure here — `LookTagSearch.find` — plus
// a `scope` the injected search *declares* about itself, so the copy and the
// ordering follow whatever gets wired without this file assuming an answer.
// Changing Sean's mind later changes one call site in the app layer.
//
// The recommendation on GLO-266 is catalog-wide with the shelf ranked first,
// reasoning that a tag is attribution rather than evidence (GLO-196), so an
// evidence rule should not gate it. That recommendation is expressed here as
// a case, not as a default.

/// One product the search offers, ready to become a `TaggedProduct`.
public struct TagSearchResult: Identifiable, Sendable, Equatable {
    public let variantID: UUID
    /// The rendered line the catalog handed over — "fenty pro filt'r · 330".
    /// Never reassembled here: the composer must not invent a shade name.
    public let label: String
    public let category: TagCategory
    /// Whether this is already on the searcher's own shelf.
    ///
    /// **Ordering only.** It is not a badge and it must never become one: a
    /// look post is attributed content, never a claim (GLO-196), so "I own
    /// this" is not a thing the tag UI asserts about a product. It decides
    /// which half of the list a row sits in and nothing else.
    public let isOnYourShelf: Bool

    public var id: UUID {
        variantID
    }

    public init(variantID: UUID, label: String, category: TagCategory, isOnYourShelf: Bool) {
        self.variantID = variantID
        self.label = label
        self.category = category
        self.isOnYourShelf = isOnYourShelf
    }

    public var tagged: TaggedProduct {
        TaggedProduct(variantID: variantID, label: label, category: category)
    }
}

/// What the wired search actually covers. The injected search declares it;
/// nothing here infers it from the results, because an empty answer would
/// then change what the screen claims about itself.
public enum LookTagSearchScope: Sendable, Equatable, CaseIterable {
    /// Your shelf only. Sean's first option. Costs an add-to-shelf detour at
    /// post time, and the ladder is the obvious door for it.
    case shelf
    /// The whole catalog, in the catalog's own order.
    case catalog
    /// The whole catalog, with what you own lifted to the top. The
    /// recommendation on GLO-266, and not yet ruled.
    case catalogShelfFirst

    /// Said out loud under the field, because a search that quietly excludes
    /// three thousand products should say that it does.
    public var line: String {
        switch self {
        case .shelf: "searching your shelf"
        case .catalog: "searching the whole catalog"
        case .catalogShelfFirst: "searching the whole catalog — your shelf first"
        }
    }

    /// Whether results split into a shelf half and a catalog half. Only the
    /// shelf-first scope does: `shelf` has nothing to contrast with, and
    /// `catalog` was told not to care.
    public var isSectioned: Bool {
        self == .catalogShelfFirst
    }

    /// The ordering, as a pure function of the scope — the one place the
    /// shelf-first decision is expressed.
    ///
    /// **Stable**: within each half the search's own relevance order is kept
    /// exactly. Re-ranking the catalog's ranking would be this client
    /// second-guessing the search, and it has no basis to.
    public func ranked(_ results: [TagSearchResult]) -> [TagSearchResult] {
        guard self == .catalogShelfFirst else { return results }
        return results.filter(\.isOnYourShelf) + results.filter { !$0.isOnYourShelf }
    }
}

/// The seam. One closure, one scope — deliberately NOT folded into
/// `LooksStore`, whose `searchShelf` is named for an answer that has not been
/// given. When the scope is ruled, `searchShelf` retires into this.
public struct LookTagSearch: Sendable {
    public var scope: LookTagSearchScope
    public var find: @Sendable (_ query: String) async throws -> [TagSearchResult]

    public init(
        scope: LookTagSearchScope,
        find: @escaping @Sendable (String) async throws -> [TagSearchResult]
    ) {
        self.scope = scope
        self.find = find
    }
}

@MainActor
@Observable
public final class LookTagSearchModel {
    /// Below this, searching the catalog returns noise. The field says so
    /// rather than showing three thousand rows.
    public static let minimumQuery = 2

    public private(set) var results: [TagSearchResult] = []
    public private(set) var isSearching = false
    /// A failed search names itself and keeps the way onward — the composer's
    /// own triad, applied to the picker.
    public private(set) var failure: String?
    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            search()
        }
    }

    public let scope: LookTagSearchScope
    private let search0: @Sendable (String) async throws -> [TagSearchResult]
    public private(set) var task: Task<Void, Never>?

    public init(_ source: LookTagSearch) {
        scope = source.scope
        search0 = source.find
    }

    /// What the results list is, when it is empty. A list with no rows and no
    /// explanation is the "room with no floor" the drawer's notes warn about.
    public enum Vacancy: Equatable {
        case tooShort
        case nothingFound
        case none
    }

    public var vacancy: Vacancy {
        guard results.isEmpty, !isSearching else { return .none }
        return trimmed.count < Self.minimumQuery ? .tooShort : .nothingFound
    }

    /// The shelf half and the catalog half, already ordered. Empty sections
    /// are dropped so an eyebrow never stands over nothing.
    public var sections: [(isShelf: Bool, results: [TagSearchResult])] {
        guard scope.isSectioned else { return results.isEmpty ? [] : [(false, results)] }
        let mine = results.filter(\.isOnYourShelf)
        let rest = results.filter { !$0.isOnYourShelf }
        return [(true, mine), (false, rest)].filter { !$0.1.isEmpty }
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func search() {
        task?.cancel()
        let text = trimmed
        guard text.count >= Self.minimumQuery else {
            results = []
            isSearching = false
            failure = nil
            return
        }
        isSearching = true
        failure = nil
        task = Task { [search0, scope] in
            do {
                let found = try await search0(text)
                // A keystroke that lands after a later one must not overwrite
                // it — the cancellation check is what keeps the field's answer
                // the field's own.
                guard !Task.isCancelled else { return }
                results = scope.ranked(found)
                isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                isSearching = false
                failure = "couldn't search just now. try again."
            }
        }
    }
}
