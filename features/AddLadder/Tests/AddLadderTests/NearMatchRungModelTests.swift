import DataKit
import Foundation
import Testing
@testable import AddLadder

@MainActor
private func model(
    hits: [CatalogHit] = [],
    ladder: Ladder = Ladder(entry: .nearMatches, query: "glow recipe")
) -> NearMatchRungModel {
    NearMatchRungModel(catalog: FakeCatalog(hits: hits), ladder: ladder)
}

@MainActor
@Test func theQueryTypedTwoRungsAgoIsNotAskedForAgain() {
    var ladder = Ladder(query: "laneige lip mask")
    ladder.noneOfThese()
    ladder.noneOfThese()
    let live = model(ladder: ladder)
    #expect(live.query == "laneige lip mask")
    #expect(live.needsAName == false)
}

@MainActor
@Test func arrivingFromAMissedScanHasAGTINButNoName() {
    // The barcode rung carries a code, never a name — so this rung has to ask
    // before it has anything to show.
    var ladder = Ladder(entry: .barcode)
    ladder.scanMissed(gtin: "0810086012343")
    let live = model(ladder: ladder)
    #expect(live.ladder.scannedGTIN == "0810086012343")
    #expect(live.needsAName)
    #expect(live.query.isEmpty)
}

@MainActor
@Test func theWayOutIsAlwaysLastAndSaysWhatItDoes() async throws {
    let live = try model(hits: [hit(name: "Watermelon Glow"), hit(name: "Dew Drops")])
    await live.search()
    #expect(live.options.count == 3)
    #expect(live.options.last == .noneOfThese(prompt: "none of these — create it"))
}

@MainActor
@Test func theWayOutIsThereWithNothingToCompareAgainst() async {
    let live = model()
    await live.search()
    #expect(live.options == [.noneOfThese(prompt: "none of these — create it")])
}

@MainActor
@Test func takingTheWayOutLandsOnCreate() {
    let live = model()
    live.choose(.noneOfThese(prompt: "none of these — create it"))
    #expect(live.ladder.rung == .create)
}

@MainActor
@Test func pickingANearMatchOpensTheShadePickRatherThanResolving() async throws {
    // Same seam as the search rung: a hit is a product, a shelf item is a
    // variant (GLO-56). This rung is the last chance to avoid a duplicate, so
    // resolving on the wrong id here creates one *and* mislabels it.
    let candidate = try hit(name: "Watermelon Glow")
    let live = model(hits: [candidate])
    await live.search()
    live.choose(.match(candidate))
    #expect(live.pickedProductID == candidate.id)
    #expect(live.ladder.resolution == nil)
    #expect(live.ladder.rung == .nearMatches)
}

@MainActor
@Test func backingOutOfTheShadePickLeavesTheCandidatesUp() async throws {
    let candidate = try hit(name: "Watermelon Glow")
    let live = model(hits: [candidate])
    await live.search()
    live.choose(.match(candidate))
    live.cancelVariantPick()
    #expect(live.pickedProductID == nil)
    #expect(live.options.count == 2)
}

@MainActor
@Test func aFailedLookupDoesNotWaveSomeoneThroughToCreate() async {
    // Showing an empty candidate list on a network error is how a user creates
    // the duplicate this rung exists to prevent.
    let catalog = FakeCatalog(failure: GlossedError(.offline, userMessage: "no connection — try again in a sec."))
    let live = NearMatchRungModel(catalog: catalog, ladder: Ladder(entry: .nearMatches, query: "glow"))
    await live.search()
    #expect(live.failure?.code == .offline)
    #expect(live.ladder.rung == .nearMatches)
}

@MainActor
@Test func typingHereRefinesWithoutMovingTheLadder() {
    let live = model()
    live.query = "glow recipe dew drops"
    #expect(live.ladder.rung == .nearMatches)
    #expect(live.ladder.query == "glow recipe dew drops")
}

@MainActor
@Test func aRetryDoesNotBrieflyLookLikeACleanEmptyResult() async {
    // The window the recap asked about: clearing `failure` when a retry starts
    // leaves no error and no candidates, which on the dedupe rung reads as
    // "nothing matched, safe to create". The failure now survives until an
    // answer replaces it.
    let catalog = FakeCatalog(failure: GlossedError(.offline, userMessage: "no connection — try again in a sec."))
    let live = NearMatchRungModel(catalog: catalog, ladder: Ladder(entry: .nearMatches, query: "glow"))
    await live.search()
    #expect(live.isCandidateListTrustworthy == false)

    live.query = "glow recipe"
    await live.search()
    #expect(live.failure != nil, "still no answer, so still no clean list")
    #expect(live.isCandidateListTrustworthy == false)
}

@MainActor
@Test func aSuccessfulRetryClearsTheFailure() async throws {
    let live = try model(hits: [hit(name: "Watermelon Glow")])
    await live.search()
    #expect(live.failure == nil)
    #expect(live.isCandidateListTrustworthy)
}
