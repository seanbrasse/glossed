import DataKit
import Foundation
import Observation

/// Rung 3: the last look before we let someone create a duplicate.
///
/// Same lookup as the search rung, different job. Rung 1 is asking "what are
/// you adding?"; this one is asking "are you sure it isn't one of these?" — the
/// dedupe middle band from tech/01 §4, where the answer is in the photo rather
/// than the name, because two shades of the same product read almost identically
/// as text.
@MainActor
@Observable
public final class NearMatchRungModel {
    public private(set) var ladder: Ladder
    public private(set) var isSearching = false
    public private(set) var failure: GlossedError?
    public private(set) var pickedProductID: UUID?

    public var query: String {
        didSet { ladder.refine(query: query) }
    }

    private var result = SearchRung.Result(hits: [], isMiss: false)
    private let rung: SearchRung
    private let domain: Domain?

    /// Seeded from the ladder, which is the point: someone who typed "laneige
    /// lip mask" two rungs ago should not be made to type it again.
    public init(catalog: any CatalogSearching, ladder: Ladder, domain: Domain? = nil) {
        rung = SearchRung(catalog: catalog)
        self.ladder = ladder
        self.domain = domain
        query = ladder.query
    }

    /// True when we arrived from a scan that missed. There is a GTIN but never
    /// a name, so this rung has to ask for one before it can show anything.
    public var needsAName: Bool {
        ladder.query.isEmpty
    }

    public var options: [LadderOption] {
        result.hits.map(LadderOption.match) + [.noneOfThese(prompt: escapePrompt)]
    }

    /// The last rung before create, so this is the one place the way out should
    /// say what it will actually do — and the frame's own words for it are
    /// "create it", which is also what the rail's fourth segment is called.
    /// "Add it yourself" named the same rung twice, differently.
    private var escapePrompt: String {
        "none of these — create it"
    }

    public func search() async {
        isSearching = true
        defer { isSearching = false }
        do {
            result = try await rung.typeahead(query, domain: domain)
            // Cleared only once an answer actually arrives. Clearing it up
            // front leaves a window with no error and no candidates, which on
            // this rung reads as "nothing matched, safe to create" — the exact
            // duplicate it exists to prevent. Keeping the last failure visible
            // through a retry says the truer thing: we still do not know.
            failure = nil
        } catch {
            result = SearchRung.Result(hits: [], isMiss: false)
            failure = error
        }
    }

    /// Whether the candidate list can be trusted as "these are all of them".
    ///
    /// The way out is always available — it is not a dead end — but a screen
    /// that cannot vouch for its list should not look like one that can.
    public var isCandidateListTrustworthy: Bool {
        failure == nil && !isSearching
    }

    public func choose(_ option: LadderOption) {
        switch option {
        case let .match(hit):
            // A hit is a product; a shelf item is a variant (GLO-56). Same
            // handoff as the search rung — picking here is not resolving.
            pickedProductID = hit.id
        case .noneOfThese:
            ladder.noneOfThese()
        }
    }

    public func pickedVariant(_ variantID: UUID) {
        ladder.matched(variantID: variantID)
    }

    public func cancelVariantPick() {
        pickedProductID = nil
    }
}
