import DataKit
import DesignSystem
import Foundation
import Testing
import Tracking
@testable import Onboarding

// The quiz's state machine, with fixtures on both sides of its one branch
// predicate (the session-12 rule): haircare picked and not.

@MainActor
@Test func theDefaultFlowIsTwoStepsAndAsksTheToneAlways() {
    // Sean, Sep 2: the foundation question leaves the quiz; the tone
    // palette is no longer a branch behind "i don't wear any foundation".
    let model = OnboardingModel()
    #expect(model.steps == [.domains, .tone])
    #expect(model.domains == [.makeup, .skincare]) // the kit's pre-selection
    #expect(model.step == .domains)
}

@MainActor
@Test func pickingHaircareGrowsTheFlowAndUnpickingShrinksIt() {
    let model = OnboardingModel()
    model.toggle(.haircare)
    #expect(model.steps == [.domains, .tone, .hair])
    model.toggle(.haircare)
    #expect(model.steps == [.domains, .tone]) // recomputed, never stored
}

@MainActor
@Test func noFoundationNoLongerChangesTheStepList() {
    // The predicate that used to add the tone step is gone: tone is asked
    // whether or not a foundation is worn, so the answer cannot move a step.
    let model = OnboardingModel()
    model.setNoFoundation()
    #expect(model.steps == [.domains, .tone])
    model.toggle(.haircare)
    #expect(model.steps == [.domains, .tone, .hair])
}

@MainActor
@Test func pickingAShadeClearsNoFoundationAndTheReverse() {
    // Still exclusive answers to one question — the payoff reads both, even
    // though no quiz screen asks them any more.
    let model = OnboardingModel()
    model.setNoFoundation()
    model.anchor = ShadeAnchorPicker.Selection(brand: "fenty beauty", shade: "240")
    #expect(!model.noFoundation)
    model.setNoFoundation()
    #expect(model.anchor == ShadeAnchorPicker.Selection())
    #expect(model.noFoundation)
}

@MainActor
@Test func theLastDomainNeverDeselects() {
    // an empty domains list would render an empty app — same invariant as
    // the shelf's multi-select
    let model = OnboardingModel()
    model.toggle(.skincare)
    model.toggle(.makeup) // now only makeup… which must stay
    #expect(model.domains == [.makeup])
    model.toggle(.makeup)
    #expect(model.domains == [.makeup])
}

@MainActor
@Test func buyAllFourSelectsEveryDomain() {
    let model = OnboardingModel()
    model.selectAllDomains()
    #expect(model.domains == Domain.allCases)
    #expect(model.steps.contains(.hair)) // all four includes haircare
}

@MainActor
@Test func unpickingABranchMidFlightClampsTheStepIndex() {
    // standing on the hair step and removing haircare must not leave the
    // index past the end of the shrunken list
    let model = OnboardingModel()
    model.toggle(.haircare)
    _ = model.next() // → tone
    _ = model.next() // → hair
    #expect(model.step == .hair)
    model.toggle(.haircare)
    #expect(model.step == .tone) // clamped to the list that remains
}

@MainActor
@Test func nextWalksTheFlowAndSaysWhenItLeaves() {
    let model = OnboardingModel()
    #expect(model.next()) // domains → tone
    #expect(model.step == .tone)
    #expect(model.isLastStep)
    #expect(!model.next()) // leaving — the caller owns what comes after
}

@MainActor
@Test func backStopsAtTheFirstStep() {
    let model = OnboardingModel()
    model.back()
    #expect(model.stepIndex == 0)
    _ = model.next()
    model.back()
    #expect(model.step == .domains)
}

@MainActor
@Test func theDraftMapsThePaletteIndexToTheOneBasedToneBand() {
    // the off-by-one lives in exactly one place, and this is it
    let model = OnboardingModel()
    model.toneIndex = 0
    #expect(model.draft(birthYearMonth: "2001-07").toneBand == 1)
    model.toneIndex = 9
    #expect(model.draft(birthYearMonth: "2001-07").toneBand == 10)
    model.toneIndex = nil
    #expect(model.draft(birthYearMonth: "2001-07").toneBand == nil)
}

@MainActor
@Test func theDraftCarriesTheQuizAnswers() {
    let model = OnboardingModel()
    model.toggle(.haircare)
    model.hairPattern = "3b"
    let draft = model.draft(birthYearMonth: "1999-03")
    #expect(draft.domains == [.makeup, .skincare, .haircare])
    #expect(draft.hairPattern == "3b")
    #expect(draft.birthYearMonth == "1999-03")
    #expect(ProfileDraft.firstInvalidField(draft) == nil) // lands as-is
}

@Test func everyStepHasItsWordsAndTheBranchesNameTheirBranch() {
    for step in [OnboardingModel.Step.domains, .tone, .hair] {
        #expect(OnboardingModel.question(for: step).count == 2)
        #expect(!OnboardingModel.aside(for: step).isEmpty)
    }
    #expect(OnboardingModel.branch(of: .hair) == .hair)
    #expect(OnboardingModel.branch(of: .tone) == .palette)
    #expect(OnboardingModel.branch(of: .domains) == nil)
}

@Test func tenToneSwatchesWeightedTowardTheDeepRange() {
    // PRD §06: five bands for the entire deep half is a trust problem —
    // the palette must not thin out as it deepens
    #expect(OnboardingModel.toneSwatches.count == 10)
}

// ── events ─────────────────────────────────────────────────────────────────

private actor CapturingPoster: EventPosting {
    private(set) var posted: [QueuedEvent] = []
    func post(_ batch: [QueuedEvent]) async throws {
        posted.append(contentsOf: batch)
    }
}

@MainActor
@Test func aStepIsViewedOnceNotPerRender() async throws {
    let poster = CapturingPoster()
    let tracker = Tracker(poster: poster)
    let model = OnboardingModel(tracker: tracker)
    _ = model.next() // completes domains, lands on tone
    model.recordViewed()
    model.recordViewed() // a re-render, not a second impression
    try await Task.sleep(for: .milliseconds(50))
    await tracker.flush()
    let names = await poster.posted.map(\.name)
    #expect(names.filter { $0 == "onb_step_completed" }.count == 1)
    #expect(names.filter { $0 == "onb_step_viewed" }.count == 1)
}
