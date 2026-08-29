import DataKit
import Foundation
import Testing
@testable import AddLadder

/// Near matches the way the app really gets them — decoded off the wire,
/// because `NearMatch` (like `CatalogHit`) has no public memberwise init.
func nearMatch(name: String, why: String, imageKey: String? = nil) throws -> NearMatch {
    let json = """
    {"id":"\(UUID().uuidString)","name":"\(name)","brand_name":"Glow Recipe",
     "category_id":"\(UUID().uuidString)",
     "category_slug":"serum","domain":"skincare","scope":"canonical",
     "catalog_image_key":\(imageKey.map { "\"\($0)\"" } ?? "null"),
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
    #expect(live.arrivedWithoutAName == false)
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
    #expect(!live.arrivedWithoutAName)
    await live.search()
    #expect(await probe.askedGTINs == ["0810086012343"])
    #expect(live.options.count == 2)
}

@MainActor
@Test func nothingTypedAndNothingScannedStillNeedsAName() {
    let live = model(ladder: Ladder(entry: .nearMatches, query: ""))
    #expect(live.arrivedWithoutAName)
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

// MARK: - GLO-176: the field must outlive the first keystroke

@MainActor
@Test func typingANameDoesNotTakeTheFieldAway() {
    // The bug this replaces: `needsAName` was derived from `ladder.query`,
    // the field binds `query`, and `query.didSet` writes through to the
    // ladder — so one character unmounted the input mid-edit and the rest of
    // the name went nowhere. Driven on the simulator by typing a single `l`.
    let live = model(ladder: Ladder(entry: .nearMatches, query: ""))
    #expect(live.arrivedWithoutAName)

    live.query = "l"
    #expect(live.arrivedWithoutAName, "one character must not remove the field")

    live.query = "laneige lip mask"
    #expect(live.arrivedWithoutAName, "nor must the rest of the name")

    // And it cannot come back by clearing the field either — the rung owes a
    // field for as long as it is on screen, not until the box is non-empty.
    live.query = ""
    #expect(live.arrivedWithoutAName)
}

@MainActor
@Test func arrivingWithSomethingToAskWithNeverShowsTheField() {
    var scanned = Ladder(entry: .barcode)
    scanned.scanMissed(gtin: "0810086012343")
    #expect(!NearMatchRungModel(catalog: FakeNearMatching(), ladder: scanned).arrivedWithoutAName)

    var carried = Ladder(query: "laneige lip mask")
    carried.noneOfThese()
    carried.noneOfThese()
    #expect(!model(ladder: carried).arrivedWithoutAName)
}

@MainActor
@Test func theSearchGateStillMovesWithTheQuery() async throws {
    // The other half of the split. `arrivedWithoutAName` is latched, but the
    // guard on `search()` must stay live or a name typed here would never be
    // asked — the field would sit there taking input that went nowhere, which
    // is the same defect wearing the opposite costume.
    let probe = try FakeNearMatching(matches: [
        nearMatch(name: "lip sleeping mask", why: "similar name — check the shade and size")
    ])
    let live = NearMatchRungModel(catalog: probe, ladder: Ladder(entry: .nearMatches, query: ""))
    #expect(live.hasNothingToAskWith)

    await live.search()
    #expect(await probe.askedGTINs.isEmpty, "nothing to ask with means nothing is asked")

    live.query = "laneige lip mask"
    #expect(!live.hasNothingToAskWith)
    await live.search()
    #expect(live.options.count == 2, "one candidate plus the way out")
}

// MARK: - GLO-177: "check the photo" only where there are photos

@MainActor
@Test func aListOfDrawingsDoesNotClaimToHavePhotos() async throws {
    // 430 of the catalog's 497 brands carry no catalog image, and this rung
    // gathers candidates by brand — so an all-drawings list is the ordinary
    // case. Telling someone to check a photo, and in the same line not to
    // trust the name, points them away from the reason lines that are the
    // only thing actually disambiguating.
    let live = try model(matches: [
        nearMatch(name: "Watermelon Glow", why: "similar name — check the shade and size"),
        nearMatch(name: "Dew Drops", why: "same brand — different product")
    ])
    await live.search()
    #expect(live.isCandidateListTrustworthy, "the list is complete — that was never the problem")
    #expect(!live.everyCandidateHasAPhoto)
}

@MainActor
@Test func oneMissingPhotoIsEnoughToDropTheClaim() async throws {
    // The instruction is comparative — "the photo, *not* the name" — so it
    // only earns its place when every row can be compared that way.
    let live = try model(matches: [
        nearMatch(name: "Watermelon Glow", why: "similar name", imageKey: "a/cut512.png"),
        nearMatch(name: "Dew Drops", why: "same brand — different product")
    ])
    await live.search()
    #expect(!live.everyCandidateHasAPhoto)
}

@MainActor
@Test func everyCandidatePhotographedEarnsTheInstruction() async throws {
    let live = try model(matches: [
        nearMatch(name: "Watermelon Glow", why: "similar name", imageKey: "a/cut512.png"),
        nearMatch(name: "Dew Drops", why: "same brand", imageKey: "b/cut512.png")
    ])
    await live.search()
    #expect(live.everyCandidateHasAPhoto)
}

@MainActor
@Test func noCandidatesIsNotVacuouslyPhotographed() async {
    // `allSatisfy` on an empty list is true, which would put "check the photo"
    // above nothing at all — the same lie in a quieter form.
    let live = model()
    await live.search()
    #expect(live.isCandidateListTrustworthy)
    #expect(!live.everyCandidateHasAPhoto)
}
