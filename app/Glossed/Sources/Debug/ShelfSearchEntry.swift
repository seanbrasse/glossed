#if DEBUG

    import DataKit
    import Shelf
    import SwiftUI

    /// Its own file for the same reason `AnchorSheetEntry` is: `ScreenEntries`
    /// sits at SwiftLint's file-length ceiling.
    ///
    /// No kit frame exists for shelf search (checked `G.Shelf` — zero
    /// occurrences); built per Sean's no-frames ruling, workshopped at
    /// review (GLO-73).
    @MainActor
    enum ShelfSearchEntry {
        static let narrowed = ScreenEntry(
            id: "shelf-search",
            title: "shelf · search, narrowed to one bay",
            note: "find-what-I-own: 'rhode' folded into the controls row, the other bays drop "
                + "out whole, and the count follows — search narrows the shelf, never the catalog"
        ) {
            searching("rhode")
        }

        static let cameUpDry = ScreenEntry(
            id: "shelf-search-empty",
            title: "shelf · search came up dry",
            note: "a designed dead end, not a blank shelf: says the search found nothing and "
                + "names the way onward (+), while the domains stay visibly on"
        ) {
            searching("velvet teddy")
        }

        private static func searching(_ query: String) -> some View {
            let model = ShelfModel(sections: ShelfFixtures.sections)
            model.searchQuery = query
            return ShelfView(model: model, startsSearching: true)
        }
    }

#endif
