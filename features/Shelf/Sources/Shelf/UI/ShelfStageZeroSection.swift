import DesignSystem
import SwiftUI

/// The cold-start shelf's glue, split out for the file ceiling (GLO-211).
///
/// Internal rather than private because Swift's `private` is file-scoped:
/// moving these here without widening them stops the extension compiling.
/// The accessibility split paid the same cost.
extension ShelfView {
    /// Opens the search field, which is what both the frame's "scan or
    /// search" button and an "add" on a pick lead to — the shelf owns no
    /// catalog screen of its own.
    func openSearch() {
        isSearchOpen = true
    }

    /// Fetched once when the cold-start screen appears. No store — fixtures,
    /// previews, the screen catalog — leaves the picks empty, and the view
    /// says it has none rather than spinning forever.
    /// The empty shelf's door is the add-ladder, not the shelf's own find
    /// field: that field searches what you own, and on an empty shelf it
    /// found nothing and could not (Sean, Sep 2: "why is there a search if
    /// we have no items? … empty state should allow users to add a product").
    /// A pick seeds the ladder with its name. Fixtures and previews hand up
    /// no door, and keep the field so a tap still does something visible.
    func addProduct(_ seed: String) {
        if let onAddProduct {
            onAddProduct(seed)
        } else {
            openSearch()
        }
    }

    func loadStageZero() async {
        guard let stageZero, stageZeroPicks.isEmpty, !stageZeroLoading else { return }
        stageZeroLoading = true
        defer { stageZeroLoading = false }
        // A failed fetch is the same render as no picks: this screen is not
        // worth an error banner over, and "no picks yet" is true either way.
        stageZeroPicks = await (try? stageZero.picks(3)) ?? []
    }

    /// Why the shelf is blank, when it is.
    ///
    /// `.nothingLogged` is not a dead end like the other four — it is the cold
    /// start, which the frame treats as the product's opening argument
    /// (GLO-211). The rest keep GLO-166's one sentence naming the way out.
    @ViewBuilder var emptySection: some View {
        if let empty = model.emptyState {
            if empty == .nothingLogged {
                ShelfStageZeroView(
                    picks: stageZeroPicks,
                    isLoading: stageZeroLoading,
                    onAdd: { pick in addProduct("\(pick.brand) \(pick.name)") },
                    onAddProduct: { addProduct("") }
                )
                .padding(.top, 6)
                .task { await loadStageZero() }
            } else {
                // The shelf is never absent. Sean, Sep 3: "filtering for only
                // makeup with no makeup products on the shelf shows no empty
                // shelf. We want an empty shelf." The sentence, then one bare
                // tier labelled for the domains on, and the same door to the
                // ladder — a dry search seeds it with what was typed, since
                // "add it with +" is what the sentence just said.
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    Text(empty.message)
                        .meta()
                        .fixedSize(horizontal: false, vertical: true)
                    ShelfBayView.bare(label: model.emptyTierLabel) {
                        addProduct(model.searchQuery.trimmingCharacters(in: .whitespaces))
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}
