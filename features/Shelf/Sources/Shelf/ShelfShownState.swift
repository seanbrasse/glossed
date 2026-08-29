import DataKit
import Foundation

// What the shelf currently *shows* — the filter/search/sort projections over
// the model's state — out of `ShelfModel.swift` for the file-length ceiling.
// Screen-state companions to `ShelfOrdering.swift`'s nonisolated rules.

public extension ShelfModel {
    /// The sections currently on, in their given order, each internally
    /// sorted, holding only what matches the search. A bay with no matches
    /// drops out whole — an empty bay would read as an empty shelf.
    /// Whether want-to-try rows are hidden right now (GLO-100): hidden only
    /// while the toggle is off AND no search is active — a search overrides
    /// the hide, because "where did I put that thing I meant to try" is a
    /// search, not a browse.
    var hidesWishlist: Bool {
        !showsWishlist && searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var shownSections: [ShelfSection] {
        sections
            .filter { selectedDomains.contains($0.domain) }
            .map { section in
                ShelfSection(
                    slug: section.slug,
                    label: section.label,
                    domain: section.domain,
                    items: ShelfModel.ordered(
                        section.items.filter {
                            $0.matches(searchQuery)
                                && !(hidesWishlist && $0.status == .wantToTry)
                        },
                        by: sort
                    )
                )
            }
            .filter { !$0.items.isEmpty }
    }

    /// A real query found nothing. Distinct from "every domain off": the empty
    /// state has to say the search came up dry, not show a bare shelf.
    var searchCameUpEmpty: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty && shownSections.isEmpty
    }

    /// The bays, for a shelf of the given inside width.
    ///
    /// A function rather than a property because packing depends on how much
    /// shelf there is, and only the view knows that. Nothing about which items
    /// are shown or in what order depends on the width — that is all decided by
    /// `shownSections`, which stays testable without a layout.
    func bays(fittingWidth width: CGFloat) -> [ShelfBay] {
        ShelfBay.bays(from: shownSections, fittingWidth: width)
    }

    /// Counts what is on screen, not what is owned. A count that ignored the
    /// filter would contradict the shelf under it.
    var shownItemCount: Int {
        shownSections.reduce(0) { $0 + $1.items.count }
    }

    /// Fragrance has no shade axis and no skin axis, so it is ranked by face-off
    /// alone. The kit says that out loud whenever fragrance is on rather than
    /// letting someone wonder why one domain behaves differently.
    var showsFragranceNote: Bool {
        selectedDomains.contains(.fragrance)
    }

    func toggle(_ domain: Domain) {
        if selectedDomains.contains(domain) {
            selectedDomains.remove(domain)
        } else {
            selectedDomains.insert(domain)
        }
    }
}
