import DataKit
import Foundation
import Observation

/// What the near-match rung asks of the catalog. DataKit is frozen, so the
/// conformance lives here (the `VariantLookup` seam's shape).
public protocol NearMatching: Sendable {
    func nearMatches(
        _ query: String,
        domain: Domain?,
        gtin: String?
    ) async throws(GlossedError) -> [NearMatch]
}

extension CatalogRepository: NearMatching {}

/// Rung 3: the last look before we let someone create a duplicate.
///
/// Since 0018 this rung finally asks its own question. Rung 1 asks "what
/// matches?"; this one asks "what might she be confusing this with?" — the
/// dedupe middle band from tech/01 §4 — and every candidate arrives with the
/// server-computed reason it qualified. A scan that missed rides along: a
/// GTIN sharing a maker prefix with something we carry is the strongest
/// signal a miss ever gives us, and it works with no name typed at all.
@MainActor
@Observable
public final class NearMatchRungModel {
    public private(set) var ladder: Ladder
    public private(set) var isSearching = false
    public private(set) var failure: GlossedError?
    /// The whole hit, for the same reason as the search rung: the logging
    /// sheet's header renders from it.
    public private(set) var pickedHit: CatalogHit?

    public var pickedProductID: UUID? {
        pickedHit?.id
    }

    public var query: String {
        didSet { ladder.refine(query: query) }
    }

    private var matches: [NearMatch] = []
    private var hasAsked = false
    private let catalog: any NearMatching
    private let domain: Domain?

    /// Seeded from the ladder, which is the point: someone who typed "laneige
    /// lip mask" two rungs ago should not be made to type it again — and a
    /// scanned code that missed arrives here too, without retyping anything.
    public init(catalog: any NearMatching, ladder: Ladder, domain: Domain? = nil) {
        self.catalog = catalog
        self.ladder = ladder
        self.domain = domain
        query = ladder.query
    }

    /// True when the rung has nothing to ask with: no name typed *and* no
    /// scanned code. A missed scan alone is enough since 0018 — the maker
    /// band answers from the GTIN — so this no longer gates on the query
    /// alone.
    public var needsAName: Bool {
        ladder.query.isEmpty && ladder.scannedGTIN == nil
    }

    public var options: [LadderOption] {
        matches.map { .match($0.hit, reason: $0.why) }
            + [.noneOfThese(prompt: escapePrompt)]
    }

    /// The last rung before create, so this is the one place the way out should
    /// say what it will actually do — and the frame's own words for it are
    /// "create it", which is also what the rail's fourth segment is called.
    private var escapePrompt: String {
        "none of these — create it"
    }

    public func search() async {
        guard !needsAName else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            matches = try await catalog.nearMatches(
                query,
                domain: domain,
                gtin: ladder.scannedGTIN
            )
            hasAsked = true
            // Cleared only once an answer actually arrives — a window with no
            // error and no candidates reads as "nothing matched, safe to
            // create", the exact duplicate this rung exists to prevent.
            failure = nil
        } catch {
            matches = []
            failure = error
        }
    }

    /// Whether the candidate list can be trusted as "these are all of them".
    ///
    /// The way out is always available — it is not a dead end — but a screen
    /// that cannot vouch for its list should not look like one that can.
    public var isCandidateListTrustworthy: Bool {
        failure == nil && !isSearching && hasAsked
    }

    public func choose(_ option: LadderOption) {
        switch option {
        case let .match(hit, _):
            // A hit is a product; a shelf item is a variant (GLO-56). Same
            // handoff as the search rung — picking here is not resolving.
            pickedHit = hit
        case .noneOfThese:
            ladder.noneOfThese()
        }
    }

    public func pickedVariant(_ variantID: UUID) {
        ladder.matched(variantID: variantID)
    }

    public func cancelVariantPick() {
        pickedHit = nil
    }
}
