#if DEBUG

    import AddLadder
    import DataKit
    import DesignSystem
    import Shelf
    import SwiftUI

    /// Every built screen, in the states worth looking at.
    ///
    /// This exists because the review step this project leans on is *looking at
    /// the screen* — `docs/HANDOFF.md` §5 — and until now that cost a throwaway
    /// edit to `GlossedApp.swift` and a revert afterwards. A review step that
    /// costs an uncommitted edit is one that gets skipped silently.
    ///
    /// **States are the point, not screens.** Both defects GLO-62 turned up and
    /// both GLO-16 turned up needed a *particular* state: three matches
    /// including a personal-scope one, a list with two products in one category,
    /// a brand long enough to overflow its sticker, a phone with no camera. A
    /// catalog of happy paths would have found none of them, so each entry below
    /// names the state and why it is here.
    @MainActor
    enum ScreenCatalog {
        static let entries: [ScreenEntry] = [
            ShelfEntries.bays,
            ShelfEntries.baysWithOverflow,
            ShelfEntries.list,
            ShelfEntries.sheetOpen,
            AnchorSheetEntry.anchorSheet,
            ShelfChipsEntry.chips,
            ShelfChipsEntry.weekRefusal,
            ShelfLifecycleEntry.removeOffered,
            ShelfLifecycleEntry.removeFailed,
            ShelfEntries.everythingOff,
            ShelfSearchEntry.narrowed,
            ShelfSearchEntry.cameUpDry,
            LadderEntries.search,
            LadderEntries.searchEmpty,
            LadderEntries.searchFailed,
            LadderEntries.barcodeNoCamera,
            LadderEntries.nearMatches,
            LadderEntries.nearMatchesAfterAMissedScan,
            CreateRungEntry.form,
            CreateRungEntry.logFailed,
            CreateRungEntry.confirmed,
            VariantPickEntry.shades,
            VariantPickEntry.soleVariant,
            VariantPickEntry.loadFailed,
            VariantPickEntry.noVariants,
            ProductEntries.backed,
            ProductEntries.thinSample,
            ProductEntries.lookupFailed,
            ProductEntries.notAnAnchor,
            ImportEntries.sourcePick,
            ImportEntries.parsed,
            ImportEntries.nothingMatched,
            ImportEntries.parseFailed,
            GalleryEntries.productMock,
            LiveShelfEntry.live
        ]
    }

    @MainActor
    struct ScreenEntry: Identifiable {
        let id: String
        /// What is on screen.
        let title: String
        /// Why this state is in the catalog — the bug it would have caught, or
        /// the rule it makes visible.
        let note: String
        @ViewBuilder let make: () -> AnyView

        init(id: String, title: String, note: String, @ViewBuilder make: @escaping () -> some View) {
            self.id = id
            self.title = title
            self.note = note
            self.make = { AnyView(make()) }
        }
    }
#endif
