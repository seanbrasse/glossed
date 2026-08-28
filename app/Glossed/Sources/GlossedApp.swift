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
                // The screen picker, not the app. Onboarding decides what a
                // release build opens on (GLO-18); until it exists there is no
                // real entry point to displace, and every screen that has been
                // built is unreachable without one of these.
                DebugScreenPicker()
            #else
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
