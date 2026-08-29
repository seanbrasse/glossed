import DataKit
import Foundation
import Testing
@testable import AddLadder

/// Near matches the way the app really gets them — decoded off the wire,
/// because `NearMatch` (like `CatalogHit`) has no public memberwise init.
func nearMatch(name: String, why: String) throws -> NearMatch {
    let json = """
    {"id":"\(UUID().uuidString)","name":"\(name)","brand_name":"Glow Recipe",
     "category_id":"\(UUID().uuidString)",
     "category_slug":"serum","domain":"skincare","scope":"canonical",
     "why":"\(why)"}
    """
    return try JSONDecoder().decode(NearMatch.self, from: Data(json.utf8))
}

actor FakeNearMatching: NearMatching {
    private let matches: [NearMatch]
    private let failure: GlossedError?
    private(set) var askedGTINs: [String?] = []

    init(matches: [NearMatch] = [], failure: GlossedError? = nil) {
        self.matches = matches
        self.failure = failure
    }

    func nearMatches(
        _: String, domain _: Domain?, gtin: String?
    ) async throws(GlossedError) -> [NearMatch] {
        askedGTINs.append(gtin)
        if let failure {
            throw failure
        }
        return matches
    }
}

@MainActor
private func model(
    matches: [NearMatch] = [],
    failure: GlossedError? = nil,
    ladder: Ladder = Ladder(entry: .nearMatches, query: "glow recipe")
) -> NearMatchRungModel {
    NearMatchRungModel(catalog: FakeNearMatching(matches: matches, failure: failure), ladder: ladder)
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
@Test func aMissedScanAloneIsEnoughToAskWith() async throws {
    // The barcode rung carries a code, never a name. Since 0018 the maker
    // band answers from the GTIN alone, so a nameless arrival is no longer
    // a dead stop — and the code reaches the store.
    var ladder = Ladder(entry: .barcode)
    ladder.scanMissed(gtin: "0810086012343")
    let probe = try FakeNearMatching(matches: [
        nearMatch(name: "pro filt'r soft matte", why: "same maker as your scan")
    ])
    let live = NearMatchRungModel(catalog: probe, ladder: ladder)
    #expect(!live.needsAName)
    await live.search()
    #expect(await probe.askedGTINs == ["0810086012343"])
    #expect(live.options.count == 2)
}

@MainActor
@Test func nothingTypedAndNothingScannedStillNeedsAName() {
    let live = model(ladder: Ladder(entry: .nearMatches, query: ""))
    #expect(live.needsAName)
}

@MainActor
@Test func everyCandidateCarriesItsReasonVerbatim() async throws {
    // The rung's instruction is "check the photo, not the name"; the why is
    // what makes that actionable — server-computed, never invented here.
    let live = try model(matches: [
        nearMatch(name: "Watermelon Glow", why: "similar name — check the shade and size"),
        nearMatch(name: "Dew Drops", why: "same brand — different product")
    ])
    await live.search()
    guard case let .match(_, reason) = live.options[0] else {
        Issue.record("expected a match first")
        return
    }
    #expect(reason == "similar name — check the shade and size")
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
    let candidate = try nearMatch(name: "Watermelon Glow", why: "similar name — check the shade and size")
    let live = model(matches: [candidate])
    await live.search()
    live.choose(.match(candidate.hit, reason: candidate.why))
    #expect(live.pickedProductID == candidate.hit.id)
    #expect(live.ladder.resolution == nil)
    #expect(live.ladder.rung == .nearMatches)
}

@MainActor
@Test func backingOutOfTheShadePickLeavesTheCandidatesUp() async throws {
    let candidate = try nearMatch(name: "Watermelon Glow", why: "similar name — check the shade and size")
    let live = model(matches: [candidate])
    await live.search()
    live.choose(.match(candidate.hit, reason: candidate.why))
    live.cancelVariantPick()
    #expect(live.pickedProductID == nil)
    #expect(live.options.count == 2)
}

@MainActor
@Test func aFailedLookupDoesNotWaveSomeoneThroughToCreate() async {
    let live = model(failure: GlossedError(.offline, userMessage: "no connection — try again in a sec."))
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
    let live = model(failure: GlossedError(.offline, userMessage: "no connection — try again in a sec."))
    await live.search()
    #expect(live.isCandidateListTrustworthy == false)

    live.query = "glow recipe"
    await live.search()
    #expect(live.failure != nil, "still no answer, so still no clean list")
    #expect(live.isCandidateListTrustworthy == false)
}

@MainActor
@Test func aSuccessfulAskClearsTheFailureAndEarnsTrust() async throws {
    let live = try model(matches: [nearMatch(name: "Watermelon Glow", why: "similar name — check the shade and size")])
    await live.search()
    #expect(live.failure == nil)
    #expect(live.isCandidateListTrustworthy)
}
