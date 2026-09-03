import DesignSystem
import Foundation
import Observation

/// FLOW 1, the whole trip, as one state machine.
///
/// Every screen in this package matched its frame already; what did not exist
/// anywhere was the **flow** — the edges between them. The sequence lived in
/// a DEBUG entry in the app layer, untested, and it disagreed with the kit's
/// own graph in three places: the tour never ran, the returning-user path had
/// no way in, and the payoff cited a fixture anchor rather than the one the
/// quiz produced. This type is the edges, in the package, under test.
///
/// The kit's `screens.jsx` navigates like this — read off `G.*` directly:
///
/// ```
/// OnbHook  → quiz | discover (apple login) | signin (phone login)
/// OnbQuiz  → payoff
/// OnbPayoff→ account
/// OnbAccount → build (signup) | discover (login) | onb-hook (back out)
/// OnbBuild → tour
/// OnbTour  → welcome
/// ```
///
/// and `screen-map.html`'s captions add the two rules the graph cannot carry:
/// the tour is "**two frames, after the shelf exists**", and a returning user
/// gets "no tour, no shelf starter, nothing re-asked."
@MainActor
@Observable
public final class OnboardingFlowModel {
    /// The thirteen frames, collapsed to the seven the app actually mounts:
    /// 2/3/3b/3c are the quiz's own step list (`OnboardingModel.steps`, which
    /// is where the conditional branches belong), and 5a–5d are the account
    /// screen's stages.
    public enum Stop: String, Equatable, Sendable {
        /// `handle` sits between the account write and the shelf starter, and
        /// the position is forced rather than chosen: `claim_handle` refuses a
        /// minor, and `is_minor_user` reads the `profiles` row that
        /// `createAccount` writes — so a handle claimed any earlier is refused
        /// for a user who is not a minor at all.
        case hook, quiz, payoff, account, handle, shelfStarter, tour, welcome
    }

    /// Which of the two paths off the start screen the user took. Login is
    /// not a shorter signup — it asks nothing and shows nothing.
    public enum Path: String, Equatable, Sendable {
        case signup, login
    }

    /// Where onboarding hands back to the app. The app owns every one of
    /// these destinations; the flow only names them.
    public enum Exit: String, Equatable, Sendable {
        /// The returning-user path, and only that. The welcome's *just
        /// browse* door used to exit here too; Sean, Sep 3: *"new accounts
        /// should land on the shelf"* — so a fresh signup has no way to this
        /// exit, and both of the welcome's doors are shelf exits.
        case discover
        case buildShelf
        case importList
    }

    public private(set) var stop = Stop.hook
    public private(set) var path = Path.signup
    /// Non-nil exactly once, when onboarding is over. The app reads it and
    /// leaves; nothing here routes.
    public private(set) var exit: Exit?

    /// One quiz for the whole trip — the account stage batch-writes ITS
    /// answers, so the two cannot be separate instances.
    public let quiz: OnboardingModel

    /// The account walk, built when the flow reaches it and never during a
    /// render. Phone login arrives at the number rather than the method pick
    /// — `G.OnbSignIn` is `G.OnbAccount` with the method already chosen.
    public private(set) var account: AccountModel?

    /// The tour is first-onboarding only ("returning users and reruns never
    /// see it"). The seen marker is device-local and the app's to keep, so it
    /// arrives as a fact rather than being stored here.
    private let showsTour: Bool

    /// Resolves the quiz's brand/product/shade into the catalog variant the
    /// payoff can ask about. Returning nil is the honest answer — the payoff
    /// then runs its neutral fallback rather than claiming anything.
    private let resolveVariant: @Sendable (String, String, String) -> UUID?

    /// The seams the account walk needs, held until the flow reaches it.
    private let store: AccountStore?
    private let today: Date

    public init(
        quiz: OnboardingModel = OnboardingModel(),
        showsTour: Bool = true,
        store: AccountStore? = nil,
        today: Date = Date(),
        resolveVariant: @escaping @Sendable (String, String, String) -> UUID? = { _, _, _ in nil }
    ) {
        self.quiz = quiz
        self.showsTour = showsTour
        self.store = store
        self.today = today
        self.resolveVariant = resolveVariant
    }

    // MARK: - the start screen's three doors

    public func createAccount() {
        path = .signup
        stop = .quiz
    }

    /// "apple lands straight in" — the kit's own edge, `OnbHook → discover`.
    public func logInWithApple() {
        path = .login
        exit = .discover
    }

    /// `OnbHook → signin`, and `G.OnbSignIn` is `G.OnbAccount` in login mode
    /// with the phone method already chosen — the kit's ruling, "so the two
    /// paths can't drift apart."
    public func logInWithPhone() {
        path = .login
        account = makeAccount()
        stop = .account
    }

    // MARK: - the signup walk

    public func quizFinished() {
        stop = .payoff
    }

    /// Back off the quiz's first question. Sean, Sep 2: *"we should also be
    /// able to go back throughout onboarding"* — and the first question had
    /// no way to the start screen at all. Answers are kept: the quiz is one
    /// instance for the trip, so a second "create an account" resumes it.
    public func quizExited() {
        stop = .hook
    }

    /// Back off the payoff, to the quiz's LAST question — where the user
    /// left, not the first one over again. The quiz's own step index is
    /// untouched, which is the whole of why the flow holds one quiz.
    public func payoffBacked() {
        stop = .quiz
    }

    public func payoffContinued() {
        // Rebuilt on each arrival: backing out to the payoff and returning
        // should offer the method pick again, not resume mid-verification.
        account = makeAccount()
        stop = .account
    }

    /// Signup's terminal is the batch write; login's is a verified code. They
    /// land in different places and that is the whole difference between the
    /// two paths.
    public func accountFinished() {
        switch path {
        case .login:
            // "no tour, no shelf starter, nothing re-asked." A returning user
            // already has a handle; asking again would be the flow re-asking
            // the one thing this path exists not to.
            exit = .discover
        case .signup where account?.accountExists == true:
            // Signup that turned out to be a returning account (Sean, Sep 2):
            // the same rule as login. The profile screen still offers the
            // claim prompt to anyone whose profile predates handles.
            exit = .discover
        case .signup:
            stop = .handle
        }
    }

    /// **Nobody reaches the app without a handle** (Sean, Aug 31). There is no
    /// skip: a handle is the profile's address (GLO-187), the thing the
    /// stranger-facing half of every screen is keyed on, and a profile without
    /// one renders "no handle yet" over its own identity block.
    public func handleClaimed() {
        stop = .shelfStarter
    }

    /// Back out of the account screen's first stage. The map: "back goes to
    /// the payoff" on signup; login came from the start screen.
    public func accountExited() {
        stop = path == .login ? .hook : .payoff
    }

    /// The missing edge. `OnbBuild → tour`, and the tour's caption is
    /// explicit that it comes "**after the shelf exists**" — which is why it
    /// cannot be moved earlier and why skipping it left frame 7 orphaned.
    public func shelfStarterFinished() {
        stop = showsTour ? .tour : .welcome
    }

    /// `OnbTour → welcome`. Skipping the tour IS seeing it — the same one
    /// shot either way.
    public func tourFinished() {
        stop = .welcome
    }

    /// The welcome offers two doors, `.buildShelf` and `.importList`, and
    /// both land on the shelf — a new account's first screen is its own
    /// shelf, not discover (Sean, Sep 3). `.discover` is not one of them.
    public func welcomeChose(_ exit: Exit) {
        assert(exit != .discover, "a fresh signup lands on the shelf; discover is login's exit")
        self.exit = exit
    }

    // MARK: - what the payoff is allowed to claim

    /// The anchor the QUIZ produced, or nil. Nothing invents one: "not
    /// listed", "i don't wear any foundation", and an unfinished pick are all
    /// nil, and a nil anchor is what makes `PayoffModel` run its neutral
    /// fallback instead of a claim.
    ///
    /// This is the whole of GLO-189 at this screen. The debug trip used to
    /// hand the payoff a fixture, so a user who answered "i don't wear any
    /// foundation" was still told "12 people wear your exact shade · fenty
    /// beauty 240 · your anchor" — a real n attached to somebody else's
    /// anchor.
    public var payoffAnchor: PayoffModel.Anchor? {
        guard
            let brand = quiz.anchor.brand,
            let product = quiz.anchor.product,
            let shade = quiz.anchor.shade,
            shade != ShadeAnchorPicker.notListed,
            !quiz.noFoundation
        else { return nil }
        return PayoffModel.Anchor(
            brand: brand,
            shadeCode: shade,
            variantID: resolveVariant(brand, product, shade)
        )
    }

    private func makeAccount() -> AccountModel {
        let model = AccountModel(mode: path == .login ? .login : .signup, store: store, today: today)
        if path == .login {
            model.choosePhone()
        }
        return model
    }
}
