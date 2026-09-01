import DataKit
import Foundation

// The profile grid contents and how they are read (GLO-261). Moved out of
// `ProfileTabsModel.swift` — with looks and shelf added it crossed SwiftLint's
// 300-line ceiling, the same remedy `RoutinesModels.swift` applied to
// `RoutinesRepository.swift`. The scope vocabulary the tab strip marks with is
// next door in `ProfileScope.swift`.

/// How the profile's tabs reach persistence. Closures, not repositories, for
/// the reason `LooksStore` and `CollectionsStore` are: features never import
/// features, and the model is driven in tests with no client present.
public struct ProfileRoutinesStore: Sendable {
    public var mine: @Sendable () async throws -> [MyRoutine]
    /// Nil means this build cannot rename a routine, and the screen then offers
    /// no way to try — the same rule the tab set follows. Never a no-op
    /// closure: a rename that silently succeeds and changes nothing is worse
    /// than one that is not offered.
    public var rename: (@Sendable (UUID, String) async throws -> Void)?
    /// Every routine's linked collections, one bulk read (0052). Nil renders
    /// no chips — the tab-set rule again.
    public var links: (@Sendable ([UUID]) async throws -> [UUID: [LinkedItem]])?
    /// Unlinks one collection from one routine. Nil renders the chips
    /// without their ×.
    public var unlinkCollection: (@Sendable (_ routineID: UUID, _ collectionID: UUID) async throws -> Void)?

    public init(
        mine: @escaping @Sendable () async throws -> [MyRoutine],
        rename: (@Sendable (UUID, String) async throws -> Void)? = nil,
        links: (@Sendable ([UUID]) async throws -> [UUID: [LinkedItem]])? = nil,
        unlinkCollection: (@Sendable (UUID, UUID) async throws -> Void)? = nil
    ) {
        self.mine = mine
        self.rename = rename
        self.links = links
        self.unlinkCollection = unlinkCollection
    }

    /// The optional-closure two-step, spelled as helpers because the compiler
    /// cannot diagnose nested closures over an optional capture.
    private static func linksRead(
        _ links: LinksRepository?
    ) -> (@Sendable ([UUID]) async throws -> [UUID: [LinkedItem]])? {
        guard let links else { return nil }
        return { try await links.linkedCollections(routineIDs: $0) }
    }

    private static func unlinkWrite(
        _ links: LinksRepository?
    ) -> (@Sendable (UUID, UUID) async throws -> Void)? {
        guard let links else { return nil }
        return { try await links.unlink(routineID: $0, collectionID: $1) }
    }

    public static func live(
        _ routines: RoutinesRepository, links: LinksRepository? = nil
    ) -> ProfileRoutinesStore {
        ProfileRoutinesStore(
            mine: { try await routines.mine() },
            // **The owner's copy, and only that.** `routines.title` is the
            // column; the title a stranger reads in browse is a separate
            // approved `public_texts` row that `browse_routines` INNER JOINs
            // on. Nothing on this screen may imply otherwise — which is why
            // the sheet's copy says nothing about who can see the new name.
            rename: { try await routines.rename(routineID: $0, to: $1) },
            links: linksRead(links),
            unlinkCollection: unlinkWrite(links)
        )
    }
}

/// One card of the collections grid.
///
/// **`visibility` is carried, reversing #393's choice, and the reason is the
/// tab mark**: collections have no account-level scope, so the only way the
/// collections tab can state its ceiling truthfully is from the rows
/// themselves. The fact is carried because it is now claimed — and it is
/// claimed in exactly one place, the mark.
///
/// `tint` is the wire word from `collections.cover_tint`, not a colour: the
/// column is nullable `text` with no check constraint, so an unrecognised
/// value is a real possibility and draws untinted rather than throwing.
public struct ProfileCollection: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let tint: String?
    /// The frame's `mono(c.count + ' products')`. A count of YOUR OWN
    /// collection — no cohort, no evidence chrome.
    public let itemN: Int
    public let visibility: PrivacyScope

    public init(
        id: UUID, title: String, tint: String?, itemN: Int,
        visibility: PrivacyScope = .onlyYou
    ) {
        self.id = id
        self.title = title
        self.tint = tint
        self.itemN = itemN
        self.visibility = visibility
    }
}

/// The collections half of the seam.
public struct ProfileCollectionsStore: Sendable {
    public var mine: @Sendable () async throws -> [ProfileCollection]
    /// Same contract as the routines rename: the owner's `collections.title`,
    /// nothing public, and nil when the build cannot do it.
    public var rename: (@Sendable (UUID, String) async throws -> Void)?

    public init(
        mine: @escaping @Sendable () async throws -> [ProfileCollection],
        rename: (@Sendable (UUID, String) async throws -> Void)? = nil
    ) {
        self.mine = mine
        self.rename = rename
    }

    /// The last of the five `live` adapters, and the only one that had to wait:
    /// `CollectionsRepository` landed in #387, after the shape above was drawn.
    ///
    /// `coverTint` is mapped to its **wire word**, not to a colour — see
    /// `ProfileCollection.tint` for why the feature carries the string and
    /// `CollectionCard` decides what it draws. `visibility` comes across
    /// because the collections tab's scope mark is the ceiling of these rows
    /// and has no account-level surface to read instead.
    public static func live(_ collections: CollectionsRepository) -> ProfileCollectionsStore {
        ProfileCollectionsStore(
            mine: {
                try await collections.mine().map {
                    ProfileCollection(
                        id: $0.collectionID,
                        title: $0.title,
                        tint: $0.coverTint?.rawValue,
                        itemN: $0.itemN,
                        visibility: $0.visibility
                    )
                }
            },
            rename: { try await collections.rename(collectionID: $0, to: $1) }
        )
    }
}

/// One tile of the shelf tab: the thing you own, named.
///
/// Named rather than pictured for the same reason the looks tile is — the
/// shelf's own cutouts need `imageBase`, which is the app layer's config and
/// not something a feature may guess at (GLO-74).
public struct ProfileShelfEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let brandName: String
    public let productName: String

    public init(id: UUID, brandName: String, productName: String) {
        self.id = id
        self.brandName = brandName
        self.productName = productName
    }
}

/// The shelf half of the seam.
public struct ProfileShelfStore: Sendable {
    public var mine: @Sendable () async throws -> [ProfileShelfEntry]

    public init(mine: @escaping @Sendable () async throws -> [ProfileShelfEntry]) {
        self.mine = mine
    }

    public static func live(_ shelf: ShelfRepository) -> ProfileShelfStore {
        ProfileShelfStore(mine: {
            try await shelf.shelf().map {
                ProfileShelfEntry(
                    id: $0.userItemID, brandName: $0.brandName, productName: $0.productName
                )
            }
        })
    }
}

/// What the rename sheet is renaming.
public struct RenameTarget: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case routine, collection
    }

    public let kind: Kind
    public let id: UUID
    public var value: String

    public init(kind: Kind, id: UUID, value: String) {
        self.kind = kind
        self.id = id
        self.value = value
    }

    /// The kit builds this by uppercasing the tab key and dropping its trailing
    /// `s` — `RENAME ROUTINE` / `RENAME COLLECTION`. Spelled out rather than
    /// derived because a string operation that happens to work on two English
    /// plurals is a trick, not a rule.
    public var eyebrow: String {
        switch kind {
        case .routine: "RENAME ROUTINE"
        case .collection: "RENAME COLLECTION"
        }
    }

    /// Which seam owns the write. Taken from the target rather than from the
    /// model's current tab, so a tab switched under an open sheet cannot send
    /// a routine's id to the collections rename.
    var tabForKind: ProfileTab {
        switch kind {
        case .routine: .routines
        case .collection: .collections
        }
    }
}
