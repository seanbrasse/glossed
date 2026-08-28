import DesignSystem
import SwiftUI

@main
struct GlossedApp: App {
    init() {
        Typography.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                // The app, on a dev session (GLO-77): boots signed in as the
                // seeded user against the local stack. The screen picker is
                // still here — launch with GLOSSED_SCREENS=1 for the catalog
                // of states, which stays the place defects are found.
                if ProcessInfo.processInfo.environment["GLOSSED_SCREENS"] != nil {
                    DebugScreenPicker()
                } else {
                    AppShell()
                }
            #else
                // Release has no sign-in path until onboarding (GLO-18) and
                // real providers (GLO-23) exist.
                PlaceholderView()
            #endif
        }
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("glossed*")
                .font(Typography.display(54))
                .foregroundStyle(Tokens.Ink.primary)
            Text("your whole shelf, ranked").meta()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Ground.milk)
    }
}
