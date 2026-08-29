import DesignSystem
import Discover
import SwiftUI

// GLO-20's tab, in its own file for AppShellProductPage's reason: `AppShell`
// sits at SwiftLint's 300-line ceiling, and the house remedy is extracting
// the computed projections.

extension AppShell {
    /// An unbuilt tab names its ticket. The tab exists because the nav is the
    /// kit's; the screen does not, and pretending otherwise helps nobody.
    /// Here rather than in `AppShell.swift` since #266 took that file to the
    /// 300-line ceiling — the same extraction that created this file.
    func unbuiltTab(_ name: String, ticket: String, line: String) -> some View {
        VStack(spacing: Tokens.Space.s2) {
            Text(name).font(Typography.display(30)).foregroundStyle(Tokens.Ink.primary)
            Text(line).meta()
            Badge("not built yet · \(ticket)", tone: .lilac)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Ground.milk)
    }

    /// The discover screen, with the shelf's identity rule: a rebuilt model
    /// is a new screen, and `.id` is what tells SwiftUI so.
    ///
    /// No tap-through yet — the product page opens from a `ShelfItem`'s
    /// variant, and a discover row names a product; wiring that crossing is
    /// GLO-20's next slice, and a tap that half-works would be worse than
    /// none (the "rank it" precedent).
    @ViewBuilder var discoverTab: some View {
        if let model = session.discoverModel {
            DiscoverView(model: model)
                .id(ObjectIdentifier(model))
        } else {
            unbuiltTab("discover", ticket: "GLO-20", line: "picked for you, from your anchor")
        }
    }
}
