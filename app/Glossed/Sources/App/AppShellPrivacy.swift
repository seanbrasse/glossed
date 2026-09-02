import DataKit
import DesignSystem
import Privacy
import Profile
import SwiftUI

// GLO-119's door, in its own file for the same reason GLO-151's crossing is:
// `AppShell` sits at SwiftLint's 300-line ceiling, so new surfaces extract
// rather than accrete.

extension AppShell {
    /// The `you` tab IS the profile now (GLO-124), with the handle claim and
    /// privacy reachable from it.
    ///
    /// Rendering the real screen here rather than adding another sheet to
    /// `AppShell` is deliberate: that file sits at SwiftLint's 300-line
    /// ceiling and another session is adding to it in parallel, so a tab that
    /// shows the thing it is named after needs no new state there at all.
    ///
    /// **The seam, wired.** Every one of the seven parameters below was
    /// defaulted to `nil` until this file filled it, and the screen's whole
    /// lower half — four tabs, their scope marks and the empty state's `+` —
    /// rendered as nothing at all. That was honest and it was also invisible:
    /// the profile redesign merged across six PRs and could not be driven.
    ///
    /// This is the crossing the handoff names: a repository in `core` and a
    /// screen in `features` belong to two lanes, and the wiring between them
    /// belongs to neither by default. Three surfaces shipped dark this way in
    /// one session — the collections adapter, the discover eyebrow, the
    /// onboarding flow. A feature is not reachable until a file in `app/`
    /// says so.
    @ViewBuilder var youTab: some View {
        if let client = session.client {
            OwnProfileView(
                store: .live(
                    social: SocialRepository(client: client),
                    safety: SafetyRepository(client: client)
                ),
                suggestionsStore: .live(SocialRepository(client: client)),
                safetyStore: .live(SafetyRepository(client: client)),
                onClaimHandle: { handleOpen = true },
                onOpenPrivacy: { privacyOpen = true },
                // Settings is a state of this screen, not a tab — the frame's
                // gear opens it (GLO-213).
                settingsStore: .live(
                    ProfileRepository(client: client), client: client,
                    safety: SafetyRepository(client: client)
                ),
                onSignedOut: { session.signedOut() },
                looksStore: .live(
                    LooksRepository(client: client),
                    // The read path's seam (GLO-272): the grid's first
                    // photos, one batched presign — the tile previews.
                    resolvePhotoURLs: { await LookPhotoURLResolver(client: client).resolve($0) }
                ),
                collectionsStore: .live(CollectionsRepository(client: client)),
                routinesStore: .live(
                    RoutinesRepository(client: client),
                    links: LinksRepository(client: client)
                ),
                // No shelfStore: Sean's Aug 31 ruling removed the shelf tab
                // from the profile — the shelf is its own surface, and the
                // store's absence is what removes the tab (the model filters
                // tabs by wired stores).
                // What the marks read. `privacy_scopes`, deliberately, and not
                // `PublicProfile.shelfVisible` — see `ProfileScopesStore`.
                scopesStore: .live(PrivacyRepository(client: client)),
                onCompose: compose,
                // The tile becomes a door (GLO-266): the app owns the
                // crossing, the same as `openProduct` and `rankingItem`.
                onOpenLook: { openLook = OpenLook(id: $0) },
                // The cards become doors too (GLO-272): click in, edit there.
                onOpenCollection: { openOwnItem = .collection($0) },
                onOpenRoutine: { openOwnItem = .routine($0) },
                // The default collection (batch 2): card leads the
                // collections tab, opens the wishlist detail.
                onOpenWantToTry: { openOwnItem = .wantToTry },
                wantToTryStore: AppShell.wantToTryStore(
                    client: client, imageBase: session.imageBase
                ),
                // The pfp door (GLO-272): prepare → presign → PUT → key.
                photoStore: .live(client: client),
                // GLO-239 closes here, not in the screen: presented from the
                // profile, the claim sheet's dismissal is a signal the profile
                // has, so it reloads instead of going on saying "no handle
                // yet" over a handle that is already public.
                handleStore: .live(SocialRepository(client: client)),
                // The moment a composer or editor closes (GLO-278): the
                // profile reloads in place rather than on the next launch.
                reloadKey: profileReloadTrip
            )
        } else {
            // `client` is nil only after sign out now that `boot()` proves the
            // session reads (see `AppSession`), and this said `not built yet ·
            // GLO-21` over a profile that is entirely built. Signing back in
            // is GLO-18/GLO-23; until then this states what is true.
            unreadableTab(
                "you",
                line: "your looks, collections, routines and shelf",
                because: "built — you're signed out"
            )
        }
    }

    /// The one crossing the profile's `+` and the drawer's doors share.
    ///
    /// A feature cannot open a composer — features never import features — so
    /// `ProfileEmptyState` hands its case up and this decides what the app has
    /// to open. Both callers route through here so the two `+` affordances can
    /// never disagree about what `a collection` does, which is how the
    /// drawer's own copy came to say `collections are being built — GLO-230`
    /// two PRs after GLO-230 merged.
    func compose(_ what: ProfileComposable) {
        switch what {
        case .look:
            // A new trip per presentation: `LooksStore.live` mints the look's
            // id once per store, so a reused composer would re-upload a second
            // look's photos into the first look's R2 namespace.
            lookTrip = UUID()
            lookOpen = true
        case .routine:
            routineTrip = UUID()
            routineOpen = true
        case .collection:
            // GLO-21's remaining half, now built. This said `a collections
            // composer is still GLO-21` for exactly one PR, and before that
            // the drawer said `collections are being built — GLO-230` for two
            // PRs after that repository merged.
            collectionTrip = UUID()
            collectionOpen = true
        }
    }
}

extension View {
    /// Presents the handle claim screen. Same client guard as privacy: the
    /// claim is scoped to the signed-in user, so there is nothing to show
    /// without one.
    func handleClaimSheet(isPresented: Binding<Bool>, client: GlossedClient?) -> some View {
        sheet(isPresented: isPresented) {
            if let client {
                HandleClaimView(store: .live(SocialRepository(client: client)))
            }
        }
    }

    /// Presents the privacy screen when a client exists. Nothing renders
    /// without one: the screen's every read is scoped to the signed-in user, so
    /// a signed-out sheet would show the all-private default as if it were the
    /// viewer's own settings.
    func privacySheet(isPresented: Binding<Bool>, client: GlossedClient?) -> some View {
        sheet(isPresented: isPresented) {
            if let client {
                PrivacyView(
                    store: .live(PrivacyRepository(client: client)),
                    // The badge switches live here now (GLO-213): they are the
                    // only path by which a body fact reaches another person,
                    // so the privacy screen is the whole answer rather than
                    // half of it.
                    badgeStore: .live(safety: SafetyRepository(client: client))
                )
            }
        }
    }
}
