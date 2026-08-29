#if DEBUG

    import DataKit
    import DesignSystem
    import Shelf
    import SwiftUI

    /// Its own file for the same reason `AnchorSheetEntry` is: `ScreenEntries`
    /// sits at SwiftLint's file-length ceiling.
    ///
    /// These states are the only place the chips + note section is drivable
    /// until GLO-16's DataKit opening lands — the live app hides the section
    /// while edits cannot persist.
    @MainActor
    enum ShelfChipsEntry {
        static let chips = ScreenEntry(
            id: "shelf-sheet-chips",
            title: "shelf · item sheet, chips + note",
            note: "the fixed vocabulary as selectable chips — applied ones wear their week badge, "
                + "toggles are optimistic with revert, and the note saves once on close"
        ) {
            sheet(item: ShelfFixtures.anchorFoundation, applied: true)
        }

        static let weekRefusal = ScreenEntry(
            id: "shelf-sheet-chips-no-week",
            title: "shelf · chips, skincare without a start date",
            note: "the week rule said out loud: a reaction chip refuses to save without started_on — "
                + "'broke me out · week 1' and '· week 10' are opposite facts"
        ) {
            sheet(
                item: ShelfItem(
                    id: UUID(),
                    brand: "rhode",
                    name: "pineapple refresh",
                    categorySlug: "cleanser",
                    categoryLabel: "cleanser",
                    domain: .skincare,
                    packaging: .bottle
                ),
                applied: false
            )
        }

        private static func sheet(item: ShelfItem, applied: Bool) -> some View {
            let vocabulary = [
                ShelfChip(id: UUID(), label: "lasted all day", valence: .like),
                ShelfChip(id: UUID(), label: "creased by 2pm", valence: .dislike),
                ShelfChip(id: UUID(), label: "broke me out", valence: .dislike)
            ]
            let appliedIDs: Set<UUID> = applied ? [vocabulary[0].id] : []
            let model = ShelfChipsModel(store: ShelfChipStore(
                vocabulary: { _, _ in vocabulary },
                applied: { _ in appliedIDs },
                apply: { _, _, _ in },
                remove: { _, _ in },
                saveNote: { _, _ in }
            ))
            model.open(item)
            return ShelfItemSheet(
                item: item,
                rankedInCategory: 3,
                onClose: {},
                chips: model
            )
            .background(Tokens.Ground.milk)
        }
    }

#endif
