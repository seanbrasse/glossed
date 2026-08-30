import DataKit
import Foundation
import Testing
@testable import Profile

private func store(
    isAvailable: @escaping @Sendable (String) async throws -> Bool = { _ in true },
    claim: @escaping @Sendable (String) async throws -> String = { $0 }
) -> HandleStore {
    HandleStore(isAvailable: isAvailable, claim: claim)
}

@Test func theShapeRuleMatchesTheDatabaseConstraint() {
    // handle_shape: ^[a-z0-9][a-z0-9_.]{1,29}$ and no `..`. Mirrored on device
    // so the field can answer while typing — input formatting, not
    // authorization, and the server still decides.
    #expect(HandleClaimModel.shapeVerdict("") == .empty)
    #expect(HandleClaimModel.shapeVerdict("a") == .tooShort)
    #expect(HandleClaimModel.shapeVerdict("_maya") == .badCharacters)
    #expect(HandleClaimModel.shapeVerdict("ma..ya") == .badCharacters)
    #expect(HandleClaimModel.shapeVerdict("maya k") == .badCharacters)
    #expect(HandleClaimModel.shapeVerdict(String(repeating: "a", count: 31)) == .badCharacters)
    #expect(HandleClaimModel.shapeVerdict("maya_k.1") == .checking)
    #expect(HandleClaimModel.shapeVerdict("a1") == .checking)
}

@MainActor
@Test func typingIsNormalizedSoWhatYouSeeIsWhatYouClaim() {
    // claim_handle lowercases and trims server-side. A field that hid that
    // would surprise someone who typed capitals and got something else.
    let model = HandleClaimModel(store: store())
    model.typed = "  MayaK  "
    #expect(model.typed == "mayak")
}

@MainActor
@Test func normalizationFixesTheServersOwnInconsistency() {
    // handle_available checks the regex on the RAW input without lowercasing,
    // while claim_handle lowercases first — so "MayaK" reads unavailable but
    // would claim fine. Normalizing before we ask makes the hint agree with
    // the answer.
    #expect(HandleClaimModel.normalize("MayaK") == "mayak")
    #expect(HandleClaimModel.shapeVerdict(HandleClaimModel.normalize("MayaK")) == .checking)
}

@MainActor
@Test func aFreeHandleBecomesClaimable() async {
    let model = HandleClaimModel(store: store(isAvailable: { _ in true }))
    model.typed = "maya_k"
    await model.checkAvailability(for: "maya_k")
    #expect(model.verdict == .available)
    #expect(model.verdict.isClaimable)
}

@MainActor
@Test func takenReservedAndBrandAreOneVerdict() async {
    // handle_available returns a single boolean. Inventing a distinction the
    // server did not make would be a guess — or would need the reserved list
    // handed to the client, which is not a thing to expose.
    let model = HandleClaimModel(store: store(isAvailable: { _ in false }))
    model.typed = "fenty"
    await model.checkAvailability(for: "fenty")
    #expect(model.verdict == .unavailable)
    #expect(!model.verdict.isClaimable)
}

@MainActor
@Test func aMalformedHandleNeverCostsARoundTrip() async {
    let checked = LockedFlag()
    let model = HandleClaimModel(store: store(isAvailable: { _ in
        await checked.set()
        return true
    }))
    model.typed = "_bad"
    await model.checkAvailability(for: "_bad")
    #expect(await !checked.value)
    #expect(model.verdict == .badCharacters)
}

@MainActor
@Test func aLateAnswerForAnAbandonedHandleIsIgnored() async {
    // Type "maya", the check starts; type "juli" before it returns. The stale
    // answer must not label the new handle.
    let model = HandleClaimModel(store: store(isAvailable: { _ in false }))
    model.typed = "maya"
    let stale = Task { await model.checkAvailability(for: "maya") }
    model.typed = "juli"
    await stale.value
    #expect(model.verdict != .unavailable)
}

@MainActor
@Test func claimingSaysTheHandleIsLive() async {
    // public_profile returns h.handle unfiltered by moderation state, so the
    // handle is reachable at once. Saying it is awaiting review understates
    // the user's exposure, which is the worse error (GLO-187).
    let model = HandleClaimModel(store: store(claim: { $0 }))
    model.typed = "maya_k"
    await model.checkAvailability(for: "maya_k")
    await model.claim()
    #expect(model.claimed == "maya_k")
    #expect(model.claimedText.contains("live"))
    #expect(!model.claimedText.contains("reviewed"))
}

@MainActor
@Test func theScreenRendersWhatTheServerStored() async {
    // claim_handle returns the handle AS STORED, which can differ from what
    // was sent. The screen renders the returned value.
    let model = HandleClaimModel(store: store(claim: { _ in "normalized_by_server" }))
    model.typed = "maya_k"
    await model.checkAvailability(for: "maya_k")
    await model.claim()
    #expect(model.claimedText.contains("normalized_by_server"))
}

@MainActor
@Test func aRefusedClaimStopsOfferingTheButton() async {
    // Someone claimed it between the check and the tap, or a rule the check
    // does not cover refused it. Either way the button must stop offering.
    struct Boom: Error {}
    let model = HandleClaimModel(store: store(claim: { _ in throw Boom() }))
    model.typed = "maya_k"
    await model.checkAvailability(for: "maya_k")
    await model.claim()
    #expect(model.claimed == nil)
    #expect(model.verdict == .unavailable)
    #expect(model.errorMessage != nil)
}

@MainActor
@Test func helperTextIsLowercaseInEveryState() {
    let model = HandleClaimModel(store: store())
    for candidate in ["", "a", "_bad", "maya_k"] {
        model.typed = candidate
        #expect(model.helperText == model.helperText.lowercased())
    }
}

private actor LockedFlag {
    private(set) var value = false
    func set() {
        value = true
    }
}
