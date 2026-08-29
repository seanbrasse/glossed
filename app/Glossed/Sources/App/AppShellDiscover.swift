import Discover
import SwiftUI

// GLO-20's tab, in its own file for AppShellProductPage's reason: `AppShell`
// sits at SwiftLint's 300-line ceiling, and the house remedy is extracting
// the computed projections.

extension AppShell {
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
