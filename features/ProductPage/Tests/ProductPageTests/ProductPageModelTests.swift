import DataKit
import DesignSystem
import Foundation
import Testing
@testable import ProductPage

private actor FakeAggregates: ShadeEvidenceReading {
    private let evidence: PayoffEvidence?
    private let failure: GlossedError?

    init(evidence: PayoffEvidence? = nil, failure: GlossedError? = nil) {
        self.evidence = evidence
        self.failure = failure
    }

    func payoff(variantID _: UUID) async throws(GlossedError) -> PayoffEvidence {
        if let failure {
            throw failure
        }
        return evidence ?? PayoffEvidence(exactShadeCount: 0, withFitCount: 0, evidenceBacked: false)
    }
}

private func item(
    brand: String = "rhode",
    name: String = "pocket blush",
    category: String = "cream blush",
    variant: String? = "freckle",
    benefit: String? = "the natural flush",
    rank: Int? = 2,
    of: Int? = 5,
    userItemID: UUID? = nil
) -> ProductPageItem {
    ProductPageItem(
        variantID: UUID(),
        brand: brand,
        name: name,
        categoryLabel: category,
        variant: variant,
        benefitLine: benefit,
        packaging: .compact,
        isAnchor: true,
        rank: rank,
        rankedInCategory: of,
        userItemID: userItemID
    )
}

@MainActor
private func model(
    _ product: ProductPageItem = item(),
    evidence: PayoffEvidence? = nil,
    failure: GlossedError? = nil
) -> ProductPageModel {
    ProductPageModel(
        product: product,
        aggregates: FakeAggregates(evidence: evidence, failure: failure)
    )
}

// MARK: - What the page is allowed to claim

@MainActor
@Test func beforeAnythingLoadsThePageClaimsNothing() {
    // Not "not enough yet" — we have not asked.
    #expect(model().shadeClaim == .unavailable)
}

@MainActor
@Test func aBackedResultCarriesItsN() async {
    let live = model(evidence: PayoffEvidence(exactShadeCount: 89, withFitCount: 60, evidenceBacked: true))
    await live.load()
    #expect(live.shadeClaim == .backed(n: 89))
}

@MainActor
@Test func theServerDecidesTheThresholdAndTheClientDoesNotReDeriveIt() async {
    // A large count that the server refuses to stand behind is still refused
    // here. The minimum sample lives in one place; a client that re-derived it
    // would drift the moment the threshold moved.
    let live = model(evidence: PayoffEvidence(exactShadeCount: 400, withFitCount: 12, evidenceBacked: false))
    await live.load()
    #expect(live.shadeClaim == .notEnoughYet)
}

@MainActor
@Test func aFailedLookupIsNeverReportedAsAThinSample() async {
    // The bug this enum exists to prevent: "not enough reports yet" tells
    // someone a product is unproven, when all that happened is a dropped
    // connection. It is the same mistake SearchRungModel keeps a separate
    // `failure` to avoid.
    let live = model(failure: GlossedError(.offline, userMessage: "no connection"))
    await live.load()
    #expect(live.shadeClaim == .unavailable)
    #expect(live.failure != nil)
}

@MainActor
@Test func aSuccessfulRetryClearsAnEarlierFailure() async {
    let live = model(evidence: PayoffEvidence(exactShadeCount: 12, withFitCount: 9, evidenceBacked: true))
    await live.load()
    #expect(live.failure == nil)
    #expect(live.shadeClaim == .backed(n: 12))
}

// MARK: - What the page writes

@MainActor
@Test func theEyebrowIsCategoryThenBrand() {
    #expect(model().eyebrow == "cream blush · rhode")
}

@MainActor
@Test func theSubtitleJoinsWhatIsThereAndOnlyWhatIsThere() {
    // A trailing "freckle · " where a benefit line should be is a separator
    // standing in for data the catalog does not return.
    #expect(model().subtitle == "freckle · the natural flush")
    #expect(model(item(benefit: nil)).subtitle == "freckle")
    #expect(model(item(variant: nil)).subtitle == "the natural flush")
    #expect(model(item(variant: nil, benefit: nil)).subtitle == nil)
}

@MainActor
@Test func rankIsShownOnlyWhenItHasSomethingToBeOutOf() {
    // "#2" with no denominator is a score, and this product has no scores.
    #expect(model().showsRank)
    #expect(model(item(rank: nil)).showsRank == false)
    #expect(model(item(of: nil)).showsRank == false)
    #expect(model(item(of: 0)).showsRank == false)
}

@MainActor
@Test func rankItIsOfferedOnlyForSomethingYouActuallyHave() {
    // A face-off orders the things you own — `rank_positions` keys on
    // `user_item_id`. A page opened from search or a leaderboard has nothing to
    // place, and offering the button there is GLO-165's defect one control
    // lower: an answer offered where it cannot be given.
    #expect(model(item(userItemID: UUID())).canRank)
    #expect(model(item(userItemID: nil)).canRank == false)
}

@MainActor
@Test func rankingAndFitAreGatedSeparately() {
    // Both need a shelf row, but only fit needs a store: this page holds the
    // fit store and writes through it, while the face-off is opened by the
    // host. Collapsing them into one flag would hide "rank it" on the debug
    // picker, where the fit store is deliberately a no-op stand-in.
    let owned = model(item(userItemID: UUID()))
    #expect(owned.canRank)
    #expect(owned.canCaptureFit == false, "no fit store was handed in")
}

// MARK: - The confidence meter's baseline

@MainActor
@Test func theMeterHasNoBaselineUntilThereIsAnAnswer() async {
    // Not zero. "0 of 5 anchors" during a network hiccup tells someone they
    // have done nothing, which is a claim about them rather than about the
    // request that failed.
    let live = model(failure: GlossedError(.offline, userMessage: "no connection"))
    #expect(live.anchorsWithFit == nil)
    await live.load()
    #expect(live.anchorsWithFit == nil)
}

@MainActor
@Test func theMeterAndTheEvidenceLineComeFromTheSameAnswer() async {
    // Both halves of the page describe the same user in the same moment. Two
    // reads would let the meter and the count disagree about who is being
    // talked about.
    let live = model(evidence: PayoffEvidence(exactShadeCount: 89, withFitCount: 2, evidenceBacked: true))
    await live.load()
    #expect(live.shadeClaim == .backed(n: 89))
    #expect(live.anchorsWithFit == 2)
}

@MainActor
@Test func aThinSampleStillHasARealAnchorCount() async {
    // `evidenceBacked` gates the claim about *other people*. How many anchors
    // you have given a fit for is a fact about you, and is not gated by it.
    let live = model(evidence: PayoffEvidence(exactShadeCount: 1, withFitCount: 3, evidenceBacked: false))
    await live.load()
    #expect(live.shadeClaim == .notEnoughYet)
    #expect(live.anchorsWithFit == 3)
}
