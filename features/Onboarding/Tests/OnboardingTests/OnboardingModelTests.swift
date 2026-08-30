import DataKit
import DesignSystem
import Foundation
import Testing
import Tracking
@testable import Onboarding

// The quiz's state machine, with fixtures on both sides of each branch
// predicate (the session-12 rule): haircare picked and not, foundation
// worn and not.

@MainActor
@Test func theDefaultFlowIsTwoStepsAndLeadsWithTheAnchorQuestion() {
    // PRD §06's reorder: no branch answers, no branch steps
    let model = OnboardingModel()
    #expect(model.steps == [.domains, .anchor])
    #expect(model.domains == [.makeup, .skincare]) // the kit's pre-selection
    #expect(model.step == .domains)
}

@MainActor
@Test func pickingHaircareGrowsTheFlowAndUnpickingShrinksIt() {
    let model = OnboardingModel()
    model.toggle(.haircare)
    #expect(model.steps == [.domains, .anchor, .hair])
    model.toggle(.haircare)
    #expect(model.steps == [.domains, .anchor]) // recomputed, never stored
}

@MainActor
@Test func noFoundationAddsTheTonePaletteStep() {
    let model = OnboardingModel()
    model.setNoFoundation()
    #expect(model.steps == [.domains, .anchor, .tone])
}

@MainActor
@Test func bothBranchesTogetherMakeTheFullFourStepFlow() {
    let model = OnboardingModel()
    model.toggle(.haircare)
    model.setNoFoundation()
    #expect(model.steps == [.domains, .anchor, .hair, .tone])
}

@MainActor
@Test func pickingAShadeClearsNoFoundationAndTheReverse() {
    // the two are exclusive answers to one question
    let model = OnboardingModel()
    model.setNoFoundation()
    model.anchor = ShadeAnchorPicker.Selection(brand: "fenty beauty", shade: "240")
    #expect(!model.noFoundation)
    #expect(model.steps == [.domains, .anchor]) // the tone step left with it
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
    _ = model.next() // → anchor
    _ = model.next() // → hair
    #expect(model.step == .hair)
    model.toggle(.haircare)
    #expect(model.step == .anchor) // clamped to the list that remains
}

@MainActor
@Test func nextWalksTheFlowAndSaysWhenItLeaves() {
    let model = OnboardingModel()
    #expect(model.next()) // domains → anchor
    #expect(model.step == .anchor)
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
    for step in [OnboardingModel.Step.domains, .anchor, .hair, .tone] {
        #expect(OnboardingModel.question(for: step).count == 2)
        #expect(!OnboardingModel.aside(for: step).isEmpty)
    }
    #expect(OnboardingModel.branch(of: .hair) == .hair)
    #expect(OnboardingModel.branch(of: .tone) == .palette)
    #expect(OnboardingModel.branch(of: .domains) == nil)
    #expect(OnboardingModel.branch(of: .anchor) == nil)
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
    _ = model.next() // completes domains, lands on anchor
    model.recordViewed()
    model.recordViewed() // a re-render, not a second impression
    try await Task.sleep(for: .milliseconds(50))
    await tracker.flush()
    let names = await poster.posted.map(\.name)
    #expect(names.filter { $0 == "onb_step_completed" }.count == 1)
    #expect(names.filter { $0 == "onb_step_viewed" }.count == 1)
}
