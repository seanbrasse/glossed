import Foundation

// The composer's link half (0050 — "link looks, collections, and routines
// together"). Its own file for the 300-line ceiling; the state it drives
// lives on the model, the way the tag board's canvas half does.

public extension ComposerModel {
    // MARK: - links (0050 — "link looks, collections, and routines together")

    func loadLinkables() async {
        guard let store else { return }
        linkables = await (try? store.linkables()) ?? LookLinkables(routines: [], collections: [])
    }

    /// SINGLE-choice since 0054 ("A look can have one collection, and one
    /// routine linked to it"): picking another replaces, picking the same
    /// deselects. The Set stays the storage — its size is just capped at one
    /// by these, the only writers.
    func toggleRoutine(_ id: UUID) {
        if linkedRoutineIDs.contains(id) {
            linkedRoutineIDs.remove(id)
        } else {
            linkedRoutineIDs = [id]
        }
    }

    func toggleCollection(_ id: UUID) {
        if linkedCollectionIDs.contains(id) {
            linkedCollectionIDs.remove(id)
        } else {
            linkedCollectionIDs = [id]
        }
    }
}

/// A linkable thing, as a pickable chip or card.
public struct LinkablePick: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    /// Collections only — the cover's word ("butter"/"cherry"/"mint"/
    /// "lilac"), so the pick can render in CARD form (Sean's Aug 31 batch 2:
    /// "the collection will show up in its card form, routine by its
    /// label"). Nil for routines, and for an untinted collection.
    public let tintWord: String?
    /// Collections only — the "N products" line the card carries.
    public let itemN: Int?

    public init(id: UUID, title: String, tintWord: String? = nil, itemN: Int? = nil) {
        self.id = id
        self.title = title
        self.tintWord = tintWord
        self.itemN = itemN
    }
}

/// What the link section offers: the caller's own routines and collections.
/// Own-only, matching the write policies — a look may not annex somebody
/// else's routine, so the picker must not offer one.
public struct LookLinkables: Sendable, Equatable {
    public let routines: [LinkablePick]
    public let collections: [LinkablePick]

    public var isEmpty: Bool {
        routines.isEmpty && collections.isEmpty
    }

    public init(routines: [LinkablePick], collections: [LinkablePick]) {
        self.routines = routines
        self.collections = collections
    }
}
