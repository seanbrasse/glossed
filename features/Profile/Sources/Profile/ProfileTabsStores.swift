import DataKit
import Foundation

// The tabs' vocabulary and their seams, split from `ProfileTabsModel.swift`
// when the rename write took that file past the 300-line ceiling (GLO-230).
// A mechanical move, nothing renamed — the same remedy `RoutinesModels.swift`
// applied to `RoutinesRepository.swift`.

/// The profile's lower half — `G.Profile`'s `Segmented ['routines','collections']`
/// and whichever tab it selects (GLO-230).
///
/// The frame declares both options unconditionally because its data is a
/// fixture. Here the set is derived from the seams the app actually filled, so
/// a segment never appears in front of a surface that cannot answer: a tab
/// whose content is "coming soon" is the drawer's `collections land with
/// GLO-21` mistake wearing different words (GLO-189).
public enum ProfileTab: String, CaseIterable, Sendable {
    case routines, collections

    /// Lowercase, like every label in the app. The kit's segment words are
    /// the enum's own.
    public var label: String {
        rawValue
    }
}

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

    public init(
        mine: @escaping @Sendable () async throws -> [MyRoutine],
        rename: (@Sendable (UUID, String) async throws -> Void)? = nil
    ) {
        self.mine = mine
        self.rename = rename
    }

    public static func live(_ routines: RoutinesRepository) -> ProfileRoutinesStore {
        ProfileRoutinesStore(
            mine: { try await routines.mine() },
            // **The owner's copy, and only that.** `routines.title` is the
            // column; the title a stranger reads in browse is a separate
            // approved `public_texts` row that `browse_routines` INNER JOINs
            // on. Nothing on this screen may imply otherwise — which is why
            // the sheet's copy says nothing about who can see the new name.
            rename: { try await routines.rename(routineID: $0, to: $1) }
        )
    }
}

/// One card of the collections grid — the whole of what the frame draws, and
/// nothing more.
///
/// **A local shape rather than DataKit's `MyCollection`, deliberately.** The
/// two carry the same facts, but `MyCollection` also carries `visibility`, and
/// a field on a struct this screen renders is an invitation to write copy
/// about it. V1 creates every collection `only_you` and no surface here can
/// change, honour or truthfully report that — copy about a scope no screen
/// controls is the GLO-208 shape. What is not carried cannot be claimed.
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

    public init(id: UUID, title: String, tint: String?, itemN: Int) {
        self.id = id
        self.title = title
        self.tint = tint
        self.itemN = itemN
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
}

/// What the rename sheet is renaming.
public struct RenameTarget: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case routine, collection
    }

    public let kind: Kind
    public let id: UUID
    public var value: String

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
