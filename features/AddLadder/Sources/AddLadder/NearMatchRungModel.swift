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
    /// say what it will actually do.
    private var escapePrompt: String {
        "none of these — add it yourself"
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
