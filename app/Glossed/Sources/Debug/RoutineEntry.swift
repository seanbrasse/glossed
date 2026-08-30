#if DEBUG

    import DataKit
    import DesignSystem
    import Foundation
    import Routines
    import SwiftUI

    /// Its own file for the same reason `LiveShelfEntry` is: `ScreenEntries`
    /// sits at SwiftLint's file-length ceiling.
    ///
    /// Three entries, not one. The composer's two best promises — *a failed
    /// save loses nothing* and *an empty shelf is explained, never blank* —
    /// live on the far side of a `RoutineStore` that has to misbehave, and a
    /// fixture that always succeeds cannot get you there. HANDOFF §0: a
    /// fixture whose answer does not depend on its input only tells you the
    /// screen did something.
    @MainActor
    enum RoutineEntry {
        /// Deliberately out of any order a routine would want, so the picked
        /// list can only match the order TAPPED — a shelf already in routine
        /// order would let shelf-order and tap-order fixtures look identical.
        private nonisolated static let shelf: [RoutineComposerModel.Step] = [
            .init(id: UUID(), name: "unseen sunscreen", brand: "supergoop"),
            .init(id: UUID(), name: "niacinamide 10% + zinc", brand: "the ordinary"),
            .init(id: UUID(), name: "birch juice moisturizer", brand: "round lab"),
            .init(id: UUID(), name: "hydrating cleanser", brand: "cerave"),
            .init(id: UUID(), name: "pro filt'r soft matte", brand: "fenty beauty")
        ]

        private static func composer(
            shelf: @escaping @Sendable () async throws -> [RoutineComposerModel.Step],
            create: @escaping @Sendable (String, String, [UUID]) async throws -> Void
        ) -> some View {
            RoutineComposerView(
                model: RoutineComposerModel(store: RoutineStore(shelf: shelf, create: create)),
                onClose: {},
                onSaved: {}
            )
        }

        static let composer = ScreenEntry(
            id: "routine-composer",
            title: "routines · new routine",
            note: "the + drawer's dead option made real: name, slot, and steps picked from the "
                + "shelf in tap order — two arrows are the whole reorder story. the shelf here is "
                + "deliberately NOT in routine order, so a list that matches your taps cannot be "
                + "shelf order wearing a disguise. no kit frame; built from the system, workshop here"
        ) {
            composer(shelf: { shelf }, create: { _, _, _ in })
        }

        static let saveFailed = ScreenEntry(
            id: "routine-composer-save-failed",
            title: "routines · the save failed",
            note: "the promise the always-succeeding fixture could not reach: a routine you "
                + "sequenced survives a write that throws. name, steps and their order must all "
                + "still be on screen, the error must arrive in words, and the button must go back "
                + "to saying 'save routine' — a composer that eats your work on a timeout is the "
                + "defect this entry exists to catch"
        ) {
            composer(shelf: { shelf }, create: { _, _, _ in throw URLError(.timedOut) })
        }

        static let emptyShelf = ScreenEntry(
            id: "routine-composer-empty-shelf",
            title: "routines · nothing to sequence",
            note: "a routine is your shelf in order, so a shelf with nothing on it is a real "
                + "state and not an error. it must SAY which of the two it is — GLO-166's rule, "
                + "that a blank explains itself — and must not offer a save it cannot honour"
        ) {
            composer(shelf: { [] }, create: { _, _, _ in })
        }
    }

#endif
