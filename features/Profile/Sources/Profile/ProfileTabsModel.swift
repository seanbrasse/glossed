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
    public private(set) var looks: [ProfileLook] = []
    public private(set) var collections: [ProfileCollection] = []
    public private(set) var routines: [MyRoutine] = []
    public private(set) var shelf: [ProfileShelfEntry] = []
    public private(set) var scopes: PrivacyScopes?
    public private(set) var isLoading = true
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

    private func note(_ error: Error, fallback: String) {
        guard errorMessage == nil else { return }
        errorMessage = (error as? GlossedError)?.userMessage ?? fallback
    }
}
