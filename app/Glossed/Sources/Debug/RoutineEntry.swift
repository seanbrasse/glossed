#if DEBUG

    import DesignSystem
    import Routines
    import SwiftUI

    /// Its own file for the same reason `LiveShelfEntry` is: `ScreenEntries`
    /// sits at SwiftLint's file-length ceiling.
    @MainActor
    enum RoutineEntry {
        static let composer = ScreenEntry(
            id: "routine-composer",
            title: "routines · new routine",
            note: "the + drawer's dead option made real: name, slot, and steps picked from the "
                + "shelf in tap order — two arrows are the whole reorder story. no kit frame; "
                + "built from the system, workshop here"
        ) {
            RoutineComposerView(
                model: RoutineComposerModel(store: RoutineStore(
                    shelf: {
                        [
                            .init(id: UUID(), name: "hydrating cleanser", brand: "cerave"),
                            .init(id: UUID(), name: "pro filt'r soft matte", brand: "fenty beauty"),
                            .init(id: UUID(), name: "niacinamide 10% + zinc", brand: "the ordinary"),
                            .init(id: UUID(), name: "birch juice moisturizer", brand: "round lab"),
                            .init(id: UUID(), name: "unseen sunscreen", brand: "supergoop")
                        ]
                    },
                    create: { _, _, _ in }
                )),
                onClose: {},
                onSaved: {}
            )
        }
    }

#endif
