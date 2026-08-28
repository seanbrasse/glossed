import Foundation

// The shelf screen's two control enums, out of `ShelfModel.swift` for the
// file-length ceiling — types, not model state, so they split cleanly.

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
