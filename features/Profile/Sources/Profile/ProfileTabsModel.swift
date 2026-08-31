import DataKit
import Foundation

// The tab set and the scope vocabulary live in `ProfileScope.swift`; the seams
// and the shapes they return live in `ProfileTabsStores.swift`; the words the
// cards wear live in `ProfileCardCopy.swift`. All three were this file until
// looks and shelf took it past SwiftLint's 300-line ceiling.

/// The profile's body of work: which tab is showing, what is in it, and what
/// each tab's scope mark says (GLO-261).
///
/// Sean, after driving the merged screen: *"users will see their bio, pfp,
/// name, and then looks as default, or collections, or routines, etc."* The
/// profile stops being a list of things you can do and becomes the things you
/// have made.
@MainActor
@Observable
public final class ProfileTabsModel {
    public var tab: ProfileTab = .looks
    public var isEditing = false
    public var renaming: RenameTarget?
    public private(set) var looks: [ProfileLook] = []
    public private(set) var collections: [ProfileCollection] = []
    public private(set) var routines: [MyRoutine] = []
    public private(set) var shelf: [ProfileShelfEntry] = []
    public private(set) var scopes: PrivacyScopes?
    public private(set) var isLoading = true
    public private(set) var isSavingRename = false
    public private(set) var errorMessage: String?

    private let looksStore: ProfileLooksStore?
    private let collectionsStore: ProfileCollectionsStore?
    private let routinesStore: ProfileRoutinesStore?
    private let shelfStore: ProfileShelfStore?
    private let scopesStore: ProfileScopesStore?

    public init(
        looks: ProfileLooksStore? = nil,
        collections: ProfileCollectionsStore? = nil,
        routines: ProfileRoutinesStore? = nil,
        shelf: ProfileShelfStore? = nil,
        scopes: ProfileScopesStore? = nil
    ) {
        looksStore = looks
        collectionsStore = collections
        routinesStore = routines
        shelfStore = shelf
        scopesStore = scopes
    }

    /// Only the tabs that have a seam behind them, in Sean's order.
    public var tabs: [ProfileTab] {
        ProfileTab.allCases.filter { available($0) }
    }

    private func available(_ tab: ProfileTab) -> Bool {
        switch tab {
        case .looks: looksStore != nil
        case .collections: collectionsStore != nil
        case .routines: routinesStore != nil
        case .shelf: shelfStore != nil
        }
    }

    // MARK: - The scope mark

    /// What the tab's mark says: the most any other person could reach in it.
    ///
    /// `nil` while the scopes are still loading, and the strip draws no mark
    /// rather than a placeholder one — a privacy signal that guesses is worse
    /// than a privacy signal that waits. `nil` also when no scopes seam is
    /// wired at all, for the same reason.
    ///
    /// The three account surfaces read `privacy_scopes` directly. Collections
    /// have no such surface, so their mark is the ceiling of the rows on the
    /// screen — see `ProfileTab.surface`.
    public func mark(for tab: ProfileTab) -> ProfileScopeMark? {
        guard let scopes else { return nil }
        if let surface = tab.surface {
            return ProfileScopeMark(scopes.scope(for: surface))
        }
        return ProfileScopeMark.ceiling(of: collections.map(\.visibility))
    }

    // MARK: - Loading

    /// Every wired tab loads together, because the strip switches between
    /// things that are already there — a tab that starts a fetch when it is
    /// tapped puts a spinner behind a control that reads as instant.
    ///
    /// One failure does not blank the others: each read keeps whatever it got,
    /// and the first message wins. A user with routines and a looks read that
    /// timed out should still see their routines.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await loadScopes()
        await read(looksStore?.mine, "looks") { self.looks = $0 }
        await read(collectionsStore?.mine, "collections") { self.collections = $0 }
        await read(routinesStore?.mine, "routines") { self.routines = $0 }
        await read(shelfStore?.mine, "shelf") { self.shelf = $0 }
        // The profile opens on looks; if that seam was never wired, open on the
        // first one that was rather than on a blank pane.
        if !available(tab), let first = tabs.first {
            tab = first
        }
    }

    /// A failed scopes read leaves every mark absent rather than defaulting to
    /// `only you`. The default is right for a user with no row — the repository
    /// already applies it — but wrong for a read that failed, where "only you"
    /// would be an assurance nobody checked.
    private func loadScopes() async {
        guard let scopesStore else { return }
        do {
            scopes = try await scopesStore.scopes()
        } catch {
            note(error, fallback: "couldn't check who can see your things.")
        }
    }

    private func read<T>(
        _ mine: (@Sendable () async throws -> [T])?,
        _ what: String,
        into: ([T]) -> Void
    ) async {
        guard let mine else { return }
        do {
            try await into(mine())
        } catch {
            note(error, fallback: "couldn't load your \(what). pull to try again.")
        }
    }

    // MARK: - Emptiness, and the +

    /// True when every wired tab is empty — the state Sean's `+` belongs to.
    ///
    /// Across all tabs rather than the showing one: *"In an empty state,
    /// you'll have a plus button that directs you to make a look, collection,
    /// routine, etc."* A `+` that appeared whenever the open tab happened to be
    /// empty would be a second create affordance sitting under the shell's own
    /// one, on a profile that is not empty at all.
    public var isEmpty: Bool {
        looks.isEmpty && collections.isEmpty && routines.isEmpty && shelf.isEmpty
    }

    private func note(_ error: Error, fallback: String) {
        guard errorMessage == nil else { return }
        errorMessage = (error as? GlossedError)?.userMessage ?? fallback
    }

    // MARK: - Edit mode (the frame's `edit profile` / `done editing`)

    /// Whether the tab now showing has anything to rename. The button is not
    /// drawn otherwise: an `edit profile` that turns nothing into a target is
    /// a control that does nothing, and this project has shipped that already.
    public var canEdit: Bool {
        renameWrite(for: tab) != nil
    }

    public var editButtonLabel: String {
        isEditing ? "done editing" : "edit profile"
    }

    /// The frame's mono hint, shown only while editing.
    public var editHint: String? {
        isEditing ? "tap any card to rename it" : nil
    }

    public func toggleEditing() {
        isEditing.toggle()
        if !isEditing {
            renaming = nil
        }
    }

    public func beginRename(_ target: RenameTarget) {
        guard isEditing, renameWrite(for: tab) != nil else { return }
        errorMessage = nil
        renaming = target
    }

    private func renameWrite(for tab: ProfileTab) -> (@Sendable (UUID, String) async throws -> Void)? {
        switch tab {
        case .routines: routinesStore?.rename
        case .collections: collectionsStore?.rename
        case .looks, .shelf: nil
        }
    }

    /// Writes the new title, then updates the row in place.
    ///
    /// In place rather than by reloading: the write returned, so the stored
    /// title is the trimmed string that was sent, and a reload would flash a
    /// spinner over a list that is already correct. The trim is done here as
    /// well as in the repository so the two cannot disagree about what landed.
    ///
    /// A blank title is refused before the round trip, in the repository's own
    /// words — `routines.title` is `not null` but has no length check, and a
    /// routine with a blank name is unaddressable in a list.
    public func saveRename() async {
        guard let target = renaming, let write = renameWrite(for: target.tabForKind) else { return }
        let trimmed = target.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "give it a name."
            return
        }
        isSavingRename = true
        defer { isSavingRename = false }
        errorMessage = nil
        do {
            try await write(target.id, trimmed)
            apply(trimmed, to: target)
            renaming = nil
        } catch {
            // The sheet stays open with what was typed. A rename that closes
            // on failure loses the words and tells you it worked.
            errorMessage = (error as? GlossedError)?.userMessage ?? "that didn't save. try again."
        }
    }

    private func apply(_ title: String, to target: RenameTarget) {
        switch target.kind {
        case .routine:
            routines = routines.map {
                guard $0.routineID == target.id else { return $0 }
                return MyRoutine(
                    routineID: $0.routineID, title: title, slot: $0.slot,
                    startedOn: $0.startedOn, createdAt: $0.createdAt, steps: $0.steps
                )
            }
        case .collection:
            collections = collections.map {
                guard $0.id == target.id else { return $0 }
                return ProfileCollection(
                    id: $0.id, title: title, tint: $0.tint,
                    itemN: $0.itemN, visibility: $0.visibility
                )
            }
        }
    }
}
