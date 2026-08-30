import DataKit
import DesignSystem
import Foundation
import Observation

/// What the product page needs from the aggregates, and nothing more.
///
/// DataKit is frozen, so the conformance lives here — and naming the one call
/// the page makes keeps a test double honest about what it stands in for.
public protocol ShadeEvidenceReading: Sendable {
    func payoff(variantID: UUID) async throws(GlossedError) -> PayoffEvidence
}

extension AggregatesRepository: ShadeEvidenceReading {}

/// One product, as `G.Product` shows it.
///
/// Feature-owned, like `Shelf`'s `ShelfItem` and for the same reason: the
/// joined read that would fill this in does not exist yet (GLO-66). What the
/// page *can* get from the core today is the shade evidence, and it does.
public struct ProductPageItem: Sendable, Equatable {
    public let variantID: UUID
    public let brand: String
    public let name: String
    /// "cream blush" — the category as a person would say it, not the slug.
    public let categoryLabel: String
    /// "freckle" — the shade or size.
    public let variant: String?
    /// "the natural flush" — `products.benefit_line`.
    public let benefitLine: String?
    public let packaging: ProductMock.Kind
    /// Anchor categories are meant to match skin, so their shade is evidence.
    /// Only they get the fit block.
    public let isAnchor: Bool
    public let rank: Int?
    /// The denominator of "#2 of 5 blushes" — how many in this category carry a
    /// rank, never how many you own.
    public let rankedInCategory: Int?
    /// The shelf row this page was opened from, when it was opened from one.
    ///
    /// Nil when the page is reached from anywhere the user does not own the
    /// product — search, a leaderboard — and that nil is what turns the fit
    /// control read-only rather than pretending to save (GLO-47).
    public let userItemID: UUID?
    /// The variant's catalog image, already resolved to a URL by whoever built
    /// the item — the feature knows nothing about buckets, same contract as
    /// `ShelfItem.catalogImageURL` (GLO-74).
    ///
    /// This page is on the catalog-image side of tech/01's render rule
    /// ("product pages/leaderboards/discover/search → catalog image"), and
    /// until GLO-153 it had no image field at all: the drawn mock was not a
    /// fallback firing, it was the only branch there was. Nil still renders
    /// the mock, which is the chain's floor and not an error.
    public let catalogImageURL: URL?

    public init(
        variantID: UUID,
        brand: String,
        name: String,
        categoryLabel: String,
        variant: String? = nil,
        benefitLine: String? = nil,
        packaging: ProductMock.Kind = .tube,
        isAnchor: Bool = false,
        rank: Int? = nil,
        rankedInCategory: Int? = nil,
        catalogImageURL: URL? = nil,
        userItemID: UUID? = nil
    ) {
        self.variantID = variantID
        self.brand = brand
        self.name = name
        self.categoryLabel = categoryLabel
        self.variant = variant
        self.benefitLine = benefitLine
        self.packaging = packaging
        self.isAnchor = isAnchor
        self.rank = rank
        self.rankedInCategory = rankedInCategory
        self.catalogImageURL = catalogImageURL
        self.userItemID = userItemID
    }
}

/// What the page is allowed to say about how many people in your shade rated
/// this — the three states kept apart on purpose.
///
/// The one that matters is `unavailable`. A lookup that failed is not evidence
/// about the world, and letting it fall through to "not enough reports yet"
/// would tell someone the product is unproven when all that happened is a
/// dropped connection. That is the same bug `SearchRungModel` carries a
/// separate `failure` for.
public enum ShadeClaim: Equatable, Sendable {
    /// The server says there is enough to stand behind, and this is the n.
    case backed(n: Int)
    /// The server says there is not enough yet. A promise, not an apology.
    case notEnoughYet
    /// We could not ask. Says nothing about the product.
    case unavailable
}

@MainActor
@Observable
public final class ProductPageModel {
    public let product: ProductPageItem
    public private(set) var isLoading = false
    public private(set) var failure: GlossedError?

    /// The fit answer on screen. Optimistic: it moves when tapped and falls
    /// back to what is actually persisted if the write fails (GLO-47).
    public private(set) var fit: Set<FitAnswer> = []
    private var persistedFit: Set<FitAnswer> = []

    private var evidence: PayoffEvidence?
    private let aggregates: any ShadeEvidenceReading
    private let fitStore: ProductFitStore?
    var fitLoadTask: Task<Void, Never>?
    var fitSaveTask: Task<Void, Never>?

    public init(
        product: ProductPageItem,
        aggregates: any ShadeEvidenceReading,
        fitStore: ProductFitStore? = nil
    ) {
        self.product = product
        self.aggregates = aggregates
        self.fitStore = fitStore
    }

    /// Whether the control can actually save. Nil `userItemID` means the page
    /// was reached without the user owning the product, and nil store means a
    /// fixture — either way the answer would go nowhere, and offering it would
    /// be the no-fake-writes rule broken on a third surface (GLO-72, GLO-151).
    public var canCaptureFit: Bool {
        product.userItemID != nil && fitStore != nil
    }

    /// Whether "rank it" can lead anywhere.
    ///
    /// A face-off asks *which do you reach for?*, and the answer is an ordering
    /// of things you have — `rank_positions` keys on `user_item_id`, so a page
    /// opened from search or a leaderboard has nothing to place. The button has
    /// been offered on those pages since GLO-47 and has done nothing but
    /// dismiss them ever since (GLO-240), which is the same defect GLO-165
    /// fixed one control higher up this screen: an answer offered where it
    /// cannot be given.
    ///
    /// Deliberately *not* also gated on the ranking store, the way
    /// `canCaptureFit` is gated on the fit store: this page does not hold that
    /// store — the host opens the face-off — so the only thing the page can
    /// honestly check is whether the product is one of yours.
    public var canRank: Bool {
        product.userItemID != nil
    }

    /// Reads the saved answer. Safe to call when the page cannot save — it
    /// simply does nothing.
    public func loadFit() {
        guard let userItemID = product.userItemID, let fitStore else { return }
        fitLoadTask = Task {
            guard let saved = try? await fitStore.load(userItemID) else { return }
            fit = saved
            persistedFit = saved
        }
    }

    /// Writes through, with the shelf sheet's rules: optimistic on screen,
    /// serialised so two saves cannot land out of order, reverted to what is
    /// persisted if the write fails.
    public func fitChanged(to answers: Set<FitAnswer>) {
        fit = answers
        guard let userItemID = product.userItemID, let fitStore else { return }
        fitSaveTask = Task { [previous = fitSaveTask] in
            await previous?.value
            do {
                try await fitStore.save(userItemID, answers)
                persistedFit = answers
            } catch {
                guard fit == answers else { return }
                fit = persistedFit
            }
        }
    }

    /// The claim, or the absence of one.
    ///
    /// `evidenceBacked` is the server's decision and this never second-guesses
    /// it: the minimum sample lives in one place, and a client that re-derived
    /// it would drift the moment the threshold moved. What the client does add
    /// is refusing to turn a failure into a verdict.
    public var shadeClaim: ShadeClaim {
        if failure != nil {
            return .unavailable
        }
        guard let evidence else { return .unavailable }
        return evidence.evidenceBacked ? .backed(n: evidence.exactShadeCount) : .notEnoughYet
    }

    /// How many anchors this user has already given a fit for, when we know.
    ///
    /// `nil` rather than `0` while the lookup is out or has failed: a meter that
    /// reads "0 of 5 anchors" during a network hiccup tells someone they have
    /// done nothing, which is a claim about them rather than about the request.
    public var anchorsWithFit: Int? {
        failure == nil ? evidence?.withFitCount : nil
    }

    /// "freckle · the natural flush", and just one of them when that is all
    /// there is — never a stray separator standing in for a variant string the
    /// catalog does not return (GLO-63).
    public var subtitle: String? {
        let parts = [product.variant, product.benefitLine].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "CREAM BLUSH · RHODE" — category first, then brand, which is the order
    /// the kit writes and the order you would say it out loud.
    public var eyebrow: String {
        "\(product.categoryLabel) · \(product.brand)"
    }

    /// Shown only when the rank has something to be out of. A bare "#2" is the
    /// star rating this product does not have.
    public var showsRank: Bool {
        product.rank != nil && (product.rankedInCategory ?? 0) > 0
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            evidence = try await aggregates.payoff(variantID: product.variantID)
            // Cleared only once an answer arrives. Clearing it up front leaves
            // a window with no error and no evidence, which reads as "not
            // enough yet" — a verdict we have not earned.
            failure = nil
        } catch {
            failure = error
        }
    }
}
