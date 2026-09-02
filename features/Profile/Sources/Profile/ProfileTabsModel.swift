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
    public internal(set) var collections: [ProfileCollection] = []
    public internal(set) var routines: [MyRoutine] = []
    /// Each routine's linked collections (0052), keyed by routine id. Loaded
    /// with the routines; missing key = no links = no chips.
    public private(set) var routineLinks: [UUID: [LinkedItem]] = [:]
    public private(set) var shelf: [ProfileShelfEntry] = []
    /// The default want-to-try collection's contents (batch 2) — loaded with
    /// the tabs so the card leads the collections grid without its own
    /// spinner. Nil store → no card, the seam rule.
    public private(set) var wantToTry: [WantToTryEntry] = []
    public private(set) var scopes: PrivacyScopes?
    public private(set) var isLoading = true
    public internal(set) var isSavingRename = false
    /// Setter internal, not private: `ProfileTabsRename.swift` is the same
    /// type split across files (the ceiling), and `private` is file-scoped.
    public internal(set) var errorMessage: String?
    private var hasLoaded = false

    let looksStore: ProfileLooksStore?
    let collectionsStore: ProfileCollectionsStore?
    let routinesStore: ProfileRoutinesStore?
    let shelfStore: ProfileShelfStore?
    private let scopesStore: ProfileScopesStore?
    private let wantToTryStore: WantToTryStore?

    public init(
        looks: ProfileLooksStore? = nil,
        collections: ProfileCollectionsStore? = nil,
        routines: ProfileRoutinesStore? = nil,
        shelf: ProfileShelfStore? = nil,
        scopes: ProfileScopesStore? = nil,
        wantToTry: WantToTryStore? = nil
    ) {
        looksStore = looks
        collectionsStore = collections
        routinesStore = routines
        shelfStore = shelf
        scopesStore = scopes
        wantToTryStore = wantToTry
    }

    public var hasWantToTry: Bool {
        wantToTryStore != nil
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
    /// **Only the shelf reads `privacy_scopes` now.** Looks, collections and
    /// routines each carry their own `visibility` since 0053 (GLO-272), so
    /// their mark is the ceiling of the rows actually on the screen.
    ///
    /// This used to hand `.looks` and `.routines` to `scopes.scope(for:)` and
    /// fall through to *collections'* ceiling for everything else — so the
    /// looks tab was marked by the collections it does not contain. Both
    /// halves were wrong and GLO-274 is where they are corrected.
    /// **The `scopes` guard covers every tab, including the three that do not
    /// read it.** That looks over-broad and is deliberate: a ceiling over rows
    /// that failed to load is an empty list, and an empty list ceilings to
    /// `only you` — which would state "nobody can see this" about things we
    /// simply did not manage to read. `scopes` failing is the signal that this
    /// screen's reads are degraded, so no tab claims anything.
    public func mark(for tab: ProfileTab) -> ProfileScopeMark? {
        guard let scopes else { return nil }
        if let surface = tab.surface {
            return ProfileScopeMark(scopes.scope(for: surface))
        }
        switch tab {
        // **Drafts do not count toward the ceiling.** `mine()` returns every
        // state, and the mark answers "the most any other person could reach"
        // — a draft reaches nobody, because `looks_public_read` tests
        // `state = 'public'` and not the visibility column. Counting one made
        // the tab read `public` over a single unpublished look, which is a
        // false alarm rather than a safe overstatement: it tells someone their
        // draft is out there.
        case .looks:
            return ProfileScopeMark.ceiling(
                of: looks.filter(\.isPublished).map(\.visibility)
            )
        case .collections: return ProfileScopeMark.ceiling(of: collections.map(\.visibility))
        case .routines: return ProfileScopeMark.ceiling(of: routines.map(\.visibility))
        case .shelf: return nil
        }
    }

    // MARK: - Loading

    /// Every wired tab loads together, because the strip switches between
    /// things that are already there — a tab that starts a fetch when it is
    /// tapped puts a spinner behind a control that reads as instant.
    ///
    /// One failure does not blank the others: each read keeps whatever it got,
    /// and the first message wins. A user with routines and a looks read that
    /// timed out should still see their routines.
    ///
    /// After the first load this refreshes in place — `isLoading` stays false,
    /// so a reload after a save updates the lists under the user rather than
    /// swapping them for a spinner (GLO-278). The message resets on entry so
    /// a recovered read does not keep an old toast on screen.
    public func load() async {
        isLoading = !hasLoaded
        errorMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }
        await loadScopes()
        await read(looksStore?.mine, "looks") { self.looks = $0 }
        await read(collectionsStore?.mine, "collections") { self.collections = $0 }
        await read(routinesStore?.mine, "routines") { self.routines = $0 }
        if let links = routinesStore?.links, !routines.isEmpty {
            routineLinks = await (try? links(routines.map(\.routineID))) ?? [:]
        }
        await read(shelfStore?.mine, "shelf") { self.shelf = $0 }
        await read(wantToTryStore?.entries, "want to try") { self.wantToTry = $0 }
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
    ///
    /// Want-to-try counts: it renders on the collections tab as the default
    /// collection, so a profile whose only content is saved products is not
    /// empty — and was reading as `nothing here yet` while holding four.
    public var isEmpty: Bool {
        looks.isEmpty && collections.isEmpty && routines.isEmpty && shelf.isEmpty && wantToTry.isEmpty
    }

    private func note(_ error: Error, fallback: String) {
        guard errorMessage == nil else { return }
        errorMessage = (error as? GlossedError)?.userMessage ?? fallback
    }

    // MARK: - Edit mode (the frame's `edit profile` / `done editing`)

    /// Whether the tab now showing has anything to rename.
    ///
    /// **This used to be the whole gate on `edit profile`, and its own comment
    /// described a promise it did not keep.** It read *"whether the tab now
    /// showing has anything to rename — an `edit profile` that turns nothing
    /// into a target is a control that does nothing, and this project has
    /// shipped that already."* But `renameWrite(for:)` switches on the tab
    /// **kind**, never on its contents, so the button drew over `no
    /// collections yet` and edit mode then offered `tap any card to rename it`
    /// with no cards on screen. Found by driving it (GLO-271's sweep,
    /// finding 05).
    ///
    /// It now means what it says: a rename target needs a writer **and** a row
    /// to point at.
    public var canRename: Bool {
        renameWrite(for: tab) != nil && !currentTabIsEmpty
    }

    /// Whether the tab now showing has any rows at all.
    private var currentTabIsEmpty: Bool {
        switch tab {
        case .looks: looks.isEmpty
        case .collections: collections.isEmpty
        case .routines: routines.isEmpty
        case .shelf: shelf.isEmpty
        }
    }

    public var editButtonLabel: String {
        isEditing ? "done editing" : "edit profile"
    }

    /// The frame's mono hint — and it may only promise what the tab can do.
    ///
    /// Silent otherwise: a hint naming an interaction that is not available on
    /// this tab is the same false claim `canRename` above was fixed for.
    public var editHint: String? {
        isEditing && canRename ? "tap any card to rename it" : nil
    }

    /// Whether the routine chips wear their × — a writer must exist.
    public var canUnlinkCollections: Bool {
        routinesStore?.unlinkCollection != nil
    }

    /// Chip off the moment the write returns, in place; a failure puts it
    /// back AND says so (the saveRename rules, both of them).
    public func unlinkCollection(_ collectionID: UUID, from routineID: UUID) async {
        guard let write = routinesStore?.unlinkCollection else { return }
        guard let removed = routineLinks[routineID]?.first(where: { $0.id == collectionID }) else { return }
        routineLinks[routineID]?.removeAll { $0.id == collectionID }
        do {
            try await write(routineID, collectionID)
        } catch {
            routineLinks[routineID, default: []].append(removed)
            note(error, fallback: "couldn't unlink that — try again.")
        }
    }

    public func toggleEditing() {
        isEditing.toggle()
        if !isEditing {
            renaming = nil
        }
    }
}
