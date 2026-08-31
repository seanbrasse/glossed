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
    /// Collections — the rest of GLO-21 — remain unbuilt; this is the profile
    /// half only, and the signed-out branch still says so.
    @ViewBuilder var youTab: some View {
        if let client = session.client {
            OwnProfileView(
                store: .live(
                    social: SocialRepository(client: client),
                    safety: SafetyRepository(client: client)
                ),
                suggestionsStore: .live(SocialRepository(client: client)),
                safetyStore: .live(SafetyRepository(client: client)),
                // `socialsStore` and `previewStore` are gone from the screen,
                // so they are gone from here rather than being defaulted away.
                // Linked socials is a setting now (GLO-261, #403) and
                // `SettingsView` builds its own; `what a stranger sees` is
                // deleted, because the scope lives on each tab. A defaulted
                // parameter nothing passes is exactly the residue this
                // redesign exists to remove.
                //
                // The four grid seams, the scopes the marks read and the `+`
                // are still unwired here — the profile renders its identity
                // block and nothing under it until they are. That is GLO-261's
                // last PR, and it is deliberately not this one: this file is
                // touched only for the call site the screen's own change
                // breaks.
                onClaimHandle: { handleOpen = true },
                onOpenPrivacy: { privacyOpen = true },
                // Settings is a state of this screen, not a tab — the frame's
                // gear opens it (GLO-213).
                settingsStore: .live(
                    ProfileRepository(client: client), client: client,
                    safety: SafetyRepository(client: client)
                ),
                onSignedOut: { session.signedOut() }
            )
        } else {
            unbuiltTab("you", ticket: "GLO-21", line: "profile · collections · settings")
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
