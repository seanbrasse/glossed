import DataKit
import Foundation

/// Why the shelf is showing nothing, when it is (GLO-166).
///
/// The shelf already had one designed empty state — a search that came up dry
/// — and `searchCameUpEmpty`'s own comment named the gap next to it:
/// *"distinct from 'every domain off': the empty state has to say the search
/// came up dry, not show a bare shelf."* Every domain off then rendered a bare
/// shelf. The state was known, described, and unhandled.
///
/// Each case here is reachable by tapping, and each one a person could arrive
/// at without understanding why their things vanished:
///
/// - every domain chip off — four taps, and the shelf is blank
/// - a domain on that holds nothing of yours
/// - a shelf that is all want-to-try, which GLO-100 hides by default
/// - a genuinely empty shelf, which is what a new account looks like
public enum ShelfEmptyState: Equatable, Sendable {
    /// A real query matched nothing.
    case searchDry
    /// No domain chips are on at all.
    case noDomains
    /// The chosen domains hold nothing of yours.
    case filteredOut
    /// Everything that would show is want-to-try, and the wishlist is hidden.
    case wishlistHidden
    /// There is nothing on the shelf at all.
    case nothingLogged

    /// What to say. One sentence, and every one of them names the way out —
    /// the rule the search message already followed and the bare shelf did
    /// not.
    public var message: String {
        switch self {
        case .searchDry: "nothing on your shelf matches — check the spelling, or add it with +"
        case .noDomains: "no domains on — turn one back on to see your shelf"
        case .filteredOut: "nothing here in those domains — try another, or add something with +"
        case .wishlistHidden: "everything here is want-to-try — tap the bookmark to show it"
        case .nothingLogged: "nothing on your shelf yet — add your first thing with +"
        }
    }
}

@MainActor
public extension ShelfModel {
    /// Everything logged, before any filter — the number the controls are
    /// gated on, so a filtered-down count can never hide them.
    var loggedItemCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    /// Sean, Sep 2: *"Why is there a search if we have no items? … There
    /// should be no filters unless there's more than one item logged."* The
    /// domain filter, the sorts, the find field and the view toggle all
    /// describe a list, and one thing is not a list.
    var showsControls: Bool {
        loggedItemCount > 1
    }

    /// Why the shelf is blank, or nil when it is not.
    ///
    /// Order matters and is the order a person would explain it in: what you
    /// typed, then what you switched off, then what is hidden, then what you
    /// have. Search first because a query is the most recent thing you did.
    var emptyState: ShelfEmptyState? {
        guard shownSections.isEmpty else { return nil }
        if searchCameUpEmpty {
            return .searchDry
        }
        if selectedDomains.isEmpty {
            return .noDomains
        }
        if sections.allSatisfy(\.items.isEmpty) {
            return .nothingLogged
        }
        if hidesWishlist, everythingInViewIsWishlist {
            return .wishlistHidden
        }
        return .filteredOut
    }

    /// Whether the only things the chosen domains hold are want-to-try.
    ///
    /// Checked against the *selected* domains rather than the whole shelf: a
    /// wishlist-only makeup shelf should say so while makeup is the filter,
    /// even if skincare has plenty.
    private var everythingInViewIsWishlist: Bool {
        let inView = sections
            .filter { selectedDomains.contains($0.domain) }
            .flatMap(\.items)
        return !inView.isEmpty && inView.allSatisfy { $0.status == .wantToTry }
    }
}
