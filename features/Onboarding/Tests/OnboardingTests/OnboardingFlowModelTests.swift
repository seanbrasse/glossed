import DataKit
import DesignSystem
import Foundation
import Testing
@testable import Onboarding

// FLOW 1's edges. Every expectation below cites either the kit's own
// navigation graph in `screens.jsx` or the screen map's `note=` caption for
// the frame — the flow is a design decision as much as any screen is, and
// until now none of it was tested anywhere.

@MainActor
@Test func theSignupTripVisitsAllSevenStopsInTheKitsOrder() {
    let flow = OnboardingFlowModel()
    #expect(flow.stop == .hook)
    flow.createAccount()
    #expect(flow.stop == .quiz)
    flow.quizFinished()
    #expect(flow.stop == .payoff)
    flow.payoffContinued()
    #expect(flow.stop == .account)
    flow.accountFinished()
    #expect(flow.stop == .handle, "nobody reaches the app without a handle (GLO-245)")
    flow.handleClaimed()
    #expect(flow.stop == .shelfStarter)
    flow.shelfStarterFinished()
    // The edge the app was missing: OnbBuild → tour, never build → welcome.
    #expect(flow.stop == .tour)
    flow.tourFinished()
    #expect(flow.stop == .welcome)
    #expect(flow.exit == nil) // the welcome's doors have not been used yet
}

@MainActor
@Test func theFirstQuestionBacksOutToTheStartScreenAndKeepsItsAnswers() {
    // Sean, Sep 2: "we should also be able to go back throughout
    // onboarding." The first question had no way back at all.
    let flow = OnboardingFlowModel()
    flow.createAccount()
    flow.quiz.toggle(.haircare)
    flow.quizExited()
    #expect(flow.stop == .hook)
    // The quiz is one instance for the trip, so coming back resumes it.
    flow.createAccount()
    #expect(flow.stop == .quiz)
    #expect(flow.quiz.domains.contains(.haircare))
}

@MainActor
@Test func thePayoffBacksUpToTheQuizsLastQuestionNotItsFirst() {
    let flow = OnboardingFlowModel()
    flow.createAccount()
    _ = flow.quiz.next() // domains → the second question
    #expect(!flow.quiz.isFirstStep)
    flow.quizFinished()
    #expect(flow.stop == .payoff)
    flow.payoffBacked()
    #expect(flow.stop == .quiz)
    #expect(!flow.quiz.isFirstStep, "back from the payoff lands where the user left, not at question one")
}

@MainActor
@Test func theShelfStarterNeverHandsStraightToTheWelcome() {
    // The regression this file exists for. "two frames, AFTER the shelf
    // exists: the face-off, then why we're here" — so the tour cannot be
    // skipped by the flow, only by a user who has already seen it.
    let flow = OnboardingFlowModel()
    flow.createAccount()
    flow.quizFinished()
    flow.payoffContinued()
    flow.accountFinished()
    flow.shelfStarterFinished()
    #expect(flow.stop != .welcome)
    #expect(flow.stop == .tour)
    #expect(TourModel.slides.count == 2)
}

@MainActor
@Test func aRerunSkipsTheTourAndOnlyTheTour() {
    // First-onboarding only: the marker is the app's (device-local), so it
    // arrives as a fact. Nothing else about the trip changes.
    let flow = OnboardingFlowModel(showsTour: false)
    flow.createAccount()
    flow.quizFinished()
    flow.payoffContinued()
    flow.accountFinished()
    #expect(flow.stop == .handle, "nobody reaches the app without a handle (GLO-245)")
    flow.handleClaimed()
    #expect(flow.stop == .shelfStarter) // still asked for
    flow.shelfStarterFinished()
    #expect(flow.stop == .welcome)
}

// ── the returning user ─────────────────────────────────────────────────────

@MainActor
@Test func appleLoginLandsStraightOnDiscover() {
    // `G.OnbHook → go('discover')`, and the map: "apple lands straight in".
    let flow = OnboardingFlowModel()
    flow.logInWithApple()
    #expect(flow.path == .login)
    #expect(flow.exit == .discover)
    #expect(flow.stop == .hook) // no screen of ours ever mounts
}

@MainActor
@Test func phoneLoginIsTwoScreensThenDiscover() throws {
    // "log in → phone number → code → straight to discover", and NOTHING
    // between: no tour, no shelf starter, no quiz, no birthday.
    let flow = OnboardingFlowModel()
    flow.logInWithPhone()
    #expect(flow.path == .login)
    #expect(flow.stop == .account)

    let account = try #require(flow.account)
    #expect(account.mode == .login)
    #expect(account.stage == .phone) // the number, not the method pick

    account.phoneNumber = "+1 555 0134"
    account.sendCode()
    account.enterCode("482913")
    account.verifyCode()
    #expect(account.isAuthenticated)
    #expect(account.birthday == nil) // never re-asked

    flow.accountFinished()
    #expect(flow.exit == .discover)
    #expect(flow.stop == .account) // it exits; it does not walk on to the tour
}

@MainActor
@Test func backingOutGoesWhereTheUserCameFrom() {
    // The map: on signup "back goes to the payoff". Login came from the
    // start screen, which is the only place it can return to.
    let signup = OnboardingFlowModel()
    signup.createAccount()
    signup.quizFinished()
    signup.payoffContinued()
    signup.accountExited()
    #expect(signup.stop == .payoff)

    let login = OnboardingFlowModel()
    login.logInWithPhone()
    login.accountExited()
    #expect(login.stop == .hook)
}

// ── the payoff's claim ─────────────────────────────────────────────────────

@MainActor
@Test func noFoundationMeansNoAnchorAndThereforeNoClaim() {
    // The defect this drives out: answering "i don't wear any foundation"
    // and still being told "12 people wear your exact shade · fenty beauty
    // 240 · your anchor". A real n on somebody else's anchor is the exact
    // thing GLO-189 forbids.
    let flow = OnboardingFlowModel(resolveVariant: { _, _, _ in UUID() })
    flow.quiz.setNoFoundation()
    #expect(flow.payoffAnchor == nil)
}

@MainActor
@Test func notListedIsAlsoNoAnchor() {
    // "not listed" is a peer of every shade at the picker, and a peer answer
    // is still not an anchor.
    let flow = OnboardingFlowModel(resolveVariant: { _, _, _ in UUID() })
    flow.quiz.anchor = ShadeAnchorPicker.Selection(
        brand: "fenty beauty",
        product: "pro filt'r soft matte",
        shade: ShadeAnchorPicker.notListed
    )
    #expect(flow.payoffAnchor == nil)
}

@MainActor
@Test func anUnfinishedPickIsNoAnchor() {
    let flow = OnboardingFlowModel(resolveVariant: { _, _, _ in UUID() })
    flow.quiz.anchor = ShadeAnchorPicker.Selection(brand: "nars", product: "double wear")
    #expect(flow.payoffAnchor == nil) // a brand and a line are not a shade
}

@MainActor
@Test func thePayoffCitesTheShadeTheQuizActuallyProduced() throws {
    let variant = UUID()
    let flow = OnboardingFlowModel(resolveVariant: { brand, _, shade in
        brand == "nars" && shade == "barcelona" ? variant : nil
    })
    flow.quiz.anchor = ShadeAnchorPicker.Selection(
        brand: "nars",
        product: "light reflecting foundation",
        shade: "barcelona"
    )
    let anchor = flow.payoffAnchor
    #expect(anchor?.brand == "nars")
    #expect(anchor?.shadeCode == "barcelona")
    #expect(anchor?.variantID == variant)
    // …and the badge says the user's own words back to them.
    #expect(try PayoffModel.anchorBadge(#require(anchor)) == "nars barcelona · your anchor")
}

@MainActor
@Test func anUnresolvableShadeIsNeutralNotInvented() {
    // The catalog has no variant for it: the honest answer is no claim, not
    // a claim with a made-up id behind it.
    let flow = OnboardingFlowModel() // default resolver returns nil
    flow.quiz.anchor = ShadeAnchorPicker.Selection(
        brand: "rare beauty",
        product: "liquid touch weightless",
        shade: "23w"
    )
    #expect(flow.payoffAnchor?.variantID == nil)

    let payoff = PayoffModel(anchor: flow.payoffAnchor, payoff: { _ in
        PayoffEvidence(exactShadeCount: 12, withFitCount: 9, evidenceBacked: true)
    })
    payoff.load()
    #expect(payoff.phase == .neutral) // never asked, so never claimed
}

// ── the branches still belong to the quiz ──────────────────────────────────

@MainActor
@Test func theFlowCarriesOneQuizWhoseBranchStaysConditional() {
    // 3b is the quiz's step list, not a stop of its own — which is why
    // picking haircare mid-flight grows the flow rather than jumping it.
    // (3c, the tone palette, stopped being a branch on Sep 2: it is asked
    // always, and the foundation question that gated it is gone.)
    let flow = OnboardingFlowModel()
    #expect(flow.quiz.steps == [.domains, .tone])
    flow.quiz.toggle(.haircare)
    #expect(flow.quiz.steps == [.domains, .tone, .hair])
    flow.quiz.setNoFoundation() // no longer moves a step
    #expect(flow.quiz.steps == [.domains, .tone, .hair])
    flow.quiz.toggle(.haircare) // unpicked — the branch goes away again
    #expect(flow.quiz.steps == [.domains, .tone])
    #expect(flow.stop == .hook) // none of this moved the flow
}

@MainActor
@Test func theWelcomesThreeDoorsAreTheOnlyWayOutOfSignup() {
    let flow = OnboardingFlowModel()
    flow.createAccount()
    flow.quizFinished()
    flow.payoffContinued()
    flow.accountFinished()
    flow.shelfStarterFinished()
    flow.tourFinished()
    #expect(flow.exit == nil)
    flow.welcomeChose(.importList)
    #expect(flow.exit == .importList)
}
