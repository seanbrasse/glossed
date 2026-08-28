import DataKit
import Foundation
import Observation

/// What the search rung shows, as one list.
///
/// "None of these" is a case of the same type as a match, not a separate thing
/// rendered underneath the list — which is how it ends up with the same border,
/// size and shadow without a designer having to remember (GLO-15, criterion 1).
public enum LadderOption: Identifiable, Equatable, Sendable {
    case match(CatalogHit)
    case noneOfThese(prompt: String)

    public var id: String {
        switch self {
        case let .match(hit): hit.id.uuidString
        case .noneOfThese: "none-of-these"
        }
    }
}

/// The search rung's state. Owns no styling and no transport — it turns typing
/// into a list of options and a ladder that has or has not moved.
@MainActor
@Observable
public final class SearchRungModel {
    public private(set) var ladder: Ladder
    /// Set when a match is picked. A search hit is a *product* — `search_catalog`
    /// returns `products.id` — and a shelf item is a variant, so choosing here
    /// opens the shade/size pick rather than resolving the ladder. Resolving on
    /// a product id would put the wrong row on the shelf.
    public private(set) var pickedProductID: UUID?
    public private(set) var isSearching = false
    /// Set when the search itself failed. Distinct from "no results": a failure
    /// is not evidence about the catalog, so the rung must not present it as an
    /// empty shelf.
    public private(set) var failure: GlossedError?

    public var query: String {
        didSet { ladder.refine(query: query) }
    }

    /// The rung's own answer, kept whole. Deriving `isMiss` from the query
    /// again here would be a second implementation of the same rule, and the
    /// two disagree the moment whitespace is involved — `" a "` is three
    /// characters and one letter.
    private var result = SearchRung.Result(hits: [], isMiss: false)
    private let rung: SearchRung
    private let domain: Domain?

    public init(catalog: any CatalogSearching, domain: Domain? = nil, query: String = "") {
        rung = SearchRung(catalog: catalog)
        self.domain = domain
        self.query = query
        ladder = Ladder(entry: .search, query: query)
    }

    /// Always ends with the way out. A rung with nothing to show is still a rung
    /// the user can leave, so this list is never empty.
    public var options: [LadderOption] {
        result.hits.map(LadderOption.match) + [.noneOfThese(prompt: escapePrompt)]
    }

    /// Names what happens next rather than just refusing: at the search rung the
    /// next rung is the scanner, so say so.
    ///
    /// Unconditional, which the frame is explicit about and the shipped version
    /// was not: `G.AddLadder` rung 0 writes this label once, whether or not the
    /// catalog had anything. Shortening it to a bare "none of these" the moment
    /// results appear is when the row stops naming where it goes — and that is
    /// exactly the case where someone needs telling, because they are looking
    /// at matches and deciding none of them is the thing in their hand.
    private var escapePrompt: String {
        "none of these — scan the barcode"
    }

    /// True only when a real query came back empty. A query too short to
    /// search is not a miss, and neither is a failure — this is the rung's own
    /// verdict, not a second guess at it.
    public var isMiss: Bool {
        failure == nil && !isSearching && result.isMiss
    }

    public func search() async {
        isSearching = true
        failure = nil
        defer { isSearching = false }
        do {
            result = try await rung.typeahead(query, domain: domain)
        } catch {
            result = SearchRung.Result(hits: [], isMiss: false)
            failure = error
        }
    }

    public func choose(_ option: LadderOption) {
        switch option {
        case let .match(hit): pickedProductID = hit.id
        case .noneOfThese: ladder.noneOfThese()
        }
    }

    /// The shade/size pick came back. Only now is there a variant to log, so
    /// only now can the ladder resolve.
    public func pickedVariant(_ variantID: UUID) {
        ladder.matched(variantID: variantID)
    }

    /// The user backed out of the shade/size pick. They are still on the search
    /// rung with their query intact, not one rung further down.
    public func cancelVariantPick() {
        pickedProductID = nil
    }
}
