import DataKit
import Foundation
import Testing
@testable import Onboarding

// The handle step's rules (Sean, Sep 2: "do a better job explaining rules
// for a good user handle. We need a char minimum, and error states") and
// the bug that sent him here: a second walk through signup hit "that's
// already on your shelf" and a dead button.

@MainActor
@Test func twoCharactersIsTooShortAndThreeIsNot() {
    let model = OnbHandleModel()
    model.typing("ab")
    #expect(model.verdict == .tooShort)
    #expect(!model.canClaim)
    model.typing("abc")
    #expect(model.verdict == .available) // no store: nothing to check against
    #expect(model.canClaim)
}

@MainActor
@Test func theShapeRulesSpeakInTheUsersWords() {
    let model = OnbHandleModel()
    model.typing(".sean")
    #expect(model.verdict == .malformed("start with a letter or number."))
    model.typing("sean..b")
    #expect(model.verdict == .malformed("one dot at a time."))
    model.typing("Sean B!")
    #expect(model.typed == "sean_b") // normalized: lowercase, space → _, ! dropped
    #expect(model.verdict == .available)
}

@MainActor
@Test func anAccountWithAHandleCarriesOnWithoutBeingAsked() async {
    let store = OnbHandleStore(
        isAvailable: { _ in true },
        claim: { _ in Issue.record("no claim for an account that has a handle"); return "" },
        existing: { "seantest" }
    )
    let model = OnbHandleModel(store: store)
    var landed = false
    model.start(onClaimed: { landed = true })
    await model.checkTask?.value
    #expect(model.verdict == .alreadyYours("seantest"))
    #expect(landed)
}

@MainActor
@Test func aSecondClaimByTheSameAccountIsNotAShelfConflict() async {
    // `handles` allows one row per user; the unique violation used to
    // surface as DataKit's generic "that's already on your shelf."
    let conflict = GlossedError(.conflict, userMessage: "that's already on your shelf.", debugDetail: "23505")
    let store = OnbHandleStore(
        isAvailable: { _ in true },
        claim: { _ in throw conflict },
        existing: { "seantest" }
    )
    let model = OnbHandleModel(store: store)
    model.typing("someoneelse")
    await model.checkTask?.value
    var landed = false
    model.claim(onClaimed: { landed = true })
    await model.claimTask?.value
    #expect(model.verdict == .alreadyYours("seantest"))
    #expect(landed)
}

@MainActor
@Test func aRaceOnTheHandleReadsAsTaken() async {
    let conflict = GlossedError(.conflict, userMessage: "that's already on your shelf.", debugDetail: "23505")
    let store = OnbHandleStore(isAvailable: { _ in true }, claim: { _ in throw conflict }, existing: { nil })
    let model = OnbHandleModel(store: store)
    model.typing("popular")
    await model.checkTask?.value
    model.claim(onClaimed: { Issue.record("a taken handle does not land") })
    await model.claimTask?.value
    #expect(model.verdict == .taken)
}

@MainActor
@Test func theServersRefusalsAreTranslated() async {
    let store = OnbHandleStore(isAvailable: { _ in true }, claim: { _ in "" })
    let reserved = GlossedError(.server, userMessage: "something broke on our side.", debugDetail: "handle reserved")
    #expect(await OnbHandleModel.claimVerdict(for: reserved, store: store) == .failed("that one\u{2019}s reserved."))
    let brand = GlossedError(
        .server,
        userMessage: "something broke on our side.",
        debugDetail: "handle matches a brand name"
    )
    if case let .failed(message) = await OnbHandleModel.claimVerdict(for: brand, store: store) {
        #expect(message.contains("brand"))
    } else {
        Issue.record("a brand-name refusal must be a failed verdict")
    }
}
