#if DEBUG

    import DesignSystem
    import Shelf
    import SwiftUI

    /// Its own file for the same reason `AnchorSheetEntry` is: `ScreenEntries`
    /// sits at SwiftLint's file-length ceiling.
    ///
    /// No kit frame exists for status/remove (checked `G.Shelf` — zero
    /// lifecycle UI anywhere in the frame); built per Sean's no-frames
    /// ruling, workshopped at review (GLO-72).
    @MainActor
    enum ShelfLifecycleEntry {
        static let removeOffered = ScreenEntry(
            id: "shelf-sheet-remove",
            title: "shelf · item sheet, remove offered",
            note: "the way off the shelf, quiet on purpose — rank it stays the pop moment; "
                + "removal arms on first tap and confirms on the second, in place"
        ) {
            ShelfItemSheet(
                item: ShelfFixtures.anchorFoundation,
                rankedInCategory: 3,
                onClose: {},
                onRemove: {}
            )
            .background(Tokens.Ground.milk)
        }

        static let removeFailed = ScreenEntry(
            id: "shelf-sheet-remove-failed",
            title: "shelf · item sheet, remove failed",
            note: "a remove that silently did not happen is an item that reappears next launch — "
                + "the sheet stays up, says why, and keeps the retry"
        ) {
            ShelfItemSheet(
                item: ShelfFixtures.anchorFoundation,
                rankedInCategory: 3,
                onClose: {},
                onRemove: {},
                removeFailure: "no connection — try again in a sec."
            )
            .background(Tokens.Ground.milk)
        }
    }

#endif
