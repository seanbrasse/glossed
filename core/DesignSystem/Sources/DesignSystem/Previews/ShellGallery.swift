import SwiftUI

private enum PreviewTab: Hashable { case discover, shelf, you }

#Preview("shell — floating nav, tab bar, drawer") {
    ShellPreview()
        .padding(Tokens.Space.s5)
        .background(Tokens.Ground.milk)
        .task { Typography.registerFonts() }
}

private struct ShellPreview: View {
    @State private var tab: PreviewTab = .shelf
    @State private var category = "blush"
    @State private var drawerOpen = false

    private let categories: [(id: String, label: String)] = [
        ("blush", "blush"), ("foundation", "foundation"), ("cleanser", "cleanser"), ("stylers", "stylers")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Text("IN-SCREEN FILTERS").eyebrow()
            TabBar(options: categories, active: $category)

            Text("THREE TABS + THE PLUS").eyebrow()
            FloatingNav(
                tabs: [
                    .init(id: PreviewTab.discover, label: "discover", glyph: .discover),
                    .init(id: PreviewTab.shelf, label: "shelf", glyph: .shelf),
                    .init(id: PreviewTab.you, label: "you", glyph: .avatar(name: "maya"))
                ],
                active: $tab,
                onPlus: { drawerOpen.toggle() }
            )

            Text("THE + DRAWER").eyebrow()
            ActionDrawer(options: [
                .init(
                    label: "add a product",
                    subtitle: "search · barcode · near matches · create",
                    systemImage: "magnifyingglass",
                    tint: .mint
                ) {},
                .init(
                    label: "import a list",
                    subtitle: "notes · csv · a screenshot",
                    systemImage: "doc.text",
                    tint: .butter
                ) {},
                .init(
                    label: "new collection",
                    subtitle: "group products your way",
                    systemImage: "folder",
                    tint: .lilac
                ) {},
                .init(
                    label: "new routine",
                    subtitle: "am / pm · ordered steps",
                    systemImage: "square.3.layers.3d",
                    tint: .cherry
                ) {}
            ])
        }
    }
}
