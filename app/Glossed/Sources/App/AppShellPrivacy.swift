import DataKit
import DesignSystem
import Privacy
import SwiftUI

// GLO-119's door, in its own file for the same reason GLO-151's crossing is:
// `AppShell` sits at SwiftLint's 300-line ceiling, so new surfaces extract
// rather than accrete.

extension AppShell {
    /// The `you` tab. The profile itself is GLO-21 and unbuilt — privacy is
    /// built, so it gets a door rather than waiting for the room. An
    /// unreachable screen is one nobody can check, including Sean.
    var youTab: some View {
        VStack(spacing: Tokens.Space.s4) {
            unbuiltTab("you", ticket: "GLO-21", line: "profile · collections · settings")
            if session.client != nil {
                Button("privacy") { privacyOpen = true }
                    .buttonStyle(.glossed(.secondary))
            }
        }
    }
}

extension View {
    /// Presents the privacy screen when a client exists. Nothing renders
    /// without one: the screen's every read is scoped to the signed-in user, so
    /// a signed-out sheet would show the all-private default as if it were the
    /// viewer's own settings.
    func privacySheet(isPresented: Binding<Bool>, client: GlossedClient?) -> some View {
        sheet(isPresented: isPresented) {
            if let client {
                PrivacyView(store: .live(PrivacyRepository(client: client)))
            }
        }
    }
}
