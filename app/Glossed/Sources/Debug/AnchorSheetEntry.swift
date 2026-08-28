#if DEBUG

    import DesignSystem
    import Shelf
    import SwiftUI

    /// Its own file for the same reason `LiveShelfEntry` is: `ScreenEntries`
    /// sits at SwiftLint's file-length ceiling, and a new state should be a new
    /// small file rather than a suppression on a long one.
    @MainActor
    enum AnchorSheetEntry {
        static let anchorSheet = ScreenEntry(
            id: "shelf-anchor-sheet",
            title: "shelf · item sheet, anchor category",
            note: "the fit section only anchors get — a saved two-axis answer (too light + too pink) "
                + "and the exact-shade evidence line. GLO-67's control, on the sheet"
        ) {
            AnchorSheetOnLaunch()
        }

        private struct AnchorSheetOnLaunch: View {
            /// The sheet's fit is a binding now (the answer outlives the sheet);
            /// the fixture holds its own so the control is still drivable here.
            @State private var fit: Set<FitAnswer> = [.tooLight, .tooPink]

            var body: some View {
                ShelfItemSheet(
                    item: ShelfFixtures.anchorFoundation,
                    rankedInCategory: 3,
                    fit: $fit,
                    exactShadeCount: 12,
                    onClose: {}
                )
                .background(Tokens.Ground.milk)
            }
        }
    }

#endif
