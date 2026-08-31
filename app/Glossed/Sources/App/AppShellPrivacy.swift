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
                looksStore: .live(LooksRepository(client: client)),
                collectionsStore: .live(CollectionsRepository(client: client)),
                routinesStore: .live(RoutinesRepository(client: client)),
                // `shelf()` pins `user_id` as of GLO-258. It did not when this
                // tab was designed: `user_items` carries OR'd own+public
                // policies and `user_shelf_items` is `security_invoker`, so
                // the unfiltered read returned a public stranger's rows into
                // your own grid. Wiring this tab before that predicate existed
                // would have put the leak on a second screen.
                shelfStore: .live(ShelfRepository(client: client)),
                // What the marks read. `privacy_scopes`, deliberately, and not
                // `PublicProfile.shelfVisible` — see `ProfileScopesStore`.
                scopesStore: .live(PrivacyRepository(client: client)),
                onCompose: compose,
                // GLO-239 closes here, not in the screen: presented from the
                // profile, the claim sheet's dismissal is a signal the profile
                // has, so it reloads instead of going on saying "no handle
                // yet" over a handle that is already public.
                handleStore: .live(SocialRepository(client: client))
            )
        } else {
            unbuiltTab("you", ticket: "GLO-21", line: "profile · collections · settings")
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
            // **The repository exists; the composer does not.** GLO-230 landed
            // `CollectionsRepository` in #387 and this profile reads it — the
            // collections tab draws real cards. What is missing is the screen
            // that makes one, which is GLO-21's remaining half. The notice
            // names the ticket that is actually open rather than the one that
            // closed, because copy that tells you a built thing is unbuilt is
            // exactly as false as the reverse (GLO-189).
            notice = "a collections composer is still GLO-21 — the tab reads them, nothing writes one yet"
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
