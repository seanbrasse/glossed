import Collections
import DataKit
import SwiftUI

// The + drawer's third door, made real — its own file for the reason
// `AppShellRoutine` and `AppShellDrawer` are: `AppShell.swift` sits at
// SwiftLint's 300-line ceiling, so a new surface extracts rather than accretes.

extension AppShell {
    /// The collection composer, hosted the way the routine composer is.
    ///
    /// **`features/Collections` was imported by nothing.** It shipped a store
    /// seam, a tint enum, a summary type and a test, and `CollectionsRepository`
    /// landed in #387 — and no line anywhere joined the two, which is why both
    /// the drawer's door and the profile's `+` ended in a notice. That is the
    /// fifth surface this session found merged and dark, after the profile's
    /// seven stores, the discover eyebrow and the face-off's two entrances.
    @ViewBuilder var collectionComposer: some View {
        if let client = session.client {
            CollectionComposerView(
                model: CollectionComposerModel(
                    store: .repository(
                        collections: CollectionsRepository(client: client),
                        shelf: ShelfRepository(client: client)
                    )
                ),
                onClose: { collectionOpen = false },
                // The composer calls this only once `create` returned, so
                // closing is not optimism. A `warning` means the collection
                // EXISTS but an item did not go in — the shell says so rather
                // than letting you find the gap yourself later.
                onSaved: { warning in
                    collectionOpen = false
                    notice = warning
                }
            )
            // One composer per presentation, the `routineTrip` rule: a cover
            // keeps its content's identity across presentations, so without
            // this a second "new collection" resumes the first one's name,
            // tint and picks (GLO-96).
            .id(collectionTrip)
        }
    }
}
