import SwiftUI

@main
struct GlossedApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
        }
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("glossed*")
                .font(.system(size: 54, weight: .heavy))
            Text("your whole shelf, ranked")
                .foregroundStyle(.secondary)
        }
    }
}
