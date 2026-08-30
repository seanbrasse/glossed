import DataKit
import Routines
import SwiftUI

// The + drawer's fourth door, made real. Its own file for the reason
// `AppShellDrawer` and `AppShellDiscover` are: `AppShell.swift` sits at
// SwiftLint's 300-line ceiling, so a new surface extracts rather than accretes.

extension AppShell {
    /// The routine composer, hosted the way the ladder is.
    ///
    /// Both halves of `RoutineStore` are real reads and writes and have been
    /// since #341/#342 — `ShelfRepository.shelf()` for what you own,
    /// `RoutinesRepository.saveDraft` for the write, under the opening Sean
    /// granted for exactly that repository. The drawer said "routines land
    /// with GLO-21" for two PRs after they landed, which is GLO-189's law
    /// running backwards: copy that tells you a built thing is unbuilt is as
    /// false as copy that tells you an unbuilt thing is built.
    @ViewBuilder var routineComposer: some View {
        if let client = session.client {
            RoutineComposerView(
                model: RoutineComposerModel(store: routineStore(client: client)),
                onClose: { routineOpen = false },
                // The composer only calls this once the write returned, so
                // closing here is not optimism — a failed save keeps the
                // screen, its title, its steps and their order, which is the
                // promise `routines · the save failed` exists to hold.
                onSaved: { routineOpen = false }
            )
            // One composer per presentation, the ladder's `ladderTrip` rule:
            // the cover keeps its content's identity across presentations, so
            // without this a second "new routine" resumes the first — a stale
            // title, a stale step list, and a reused routine id across two
            // distinct intentions (GLO-96).
            .id(routineTrip)
        }
    }

    /// The two seams `RoutineComposerModel` leaves for the app, because a
    /// feature may not import DataKit's repositories through another feature.
    private func routineStore(client: GlossedClient) -> RoutineStore {
        let shelf = ShelfRepository(client: client)
        let routines = RoutinesRepository(client: client)
        return RoutineStore(
            shelf: {
                // A routine is a sequence of things you OWN — `routine_steps`
                // references `user_items`, never products — so the composer's
                // step id IS the shelf row's `userItemID`, and the write below
                // hands those straight through.
                try await shelf.shelf().map {
                    RoutineComposerModel.Step(
                        id: $0.userItemID, name: $0.productName, brand: $0.brandName
                    )
                }
            },
            create: { title, slot, stepItemIDs in
                // `RoutineComposerModel.Slot` and DataKit's `RoutineSlot` share
                // their raw values (`am` / `pm`) but not their type: the
                // composer is a feature and may not import the wider slot set
                // browse uses. A slot that does not round-trip is a bug in one
                // of the two enums, not a user error, so it fails loudly here
                // rather than silently writing `am`.
                guard let routineSlot = RoutineSlot(rawValue: slot) else {
                    throw GlossedError(
                        .unknown,
                        userMessage: "couldn't save that routine — try again",
                        debugDetail: "composer slot '\(slot)' is not a RoutineSlot"
                    )
                }
                _ = try await routines.saveDraft(
                    RoutineDraft(title: title, slot: routineSlot, stepItemIDs: stepItemIDs)
                )
            }
        )
    }
}
