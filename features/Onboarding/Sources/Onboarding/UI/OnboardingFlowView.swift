import DataKit
import DesignSystem
import SwiftUI

/// FLOW 1, mounted. One view for the whole trip, so the app layer wires an
/// entry point rather than a sequence — the sequence is `OnboardingFlowModel`
/// and it is tested.
///
/// Built to `G.OnbHook` → `G.OnbQuiz` → `G.OnbPayoff` → `G.OnbAccount` →
/// `G.OnbBuild` → `G.OnbTour` → `G.OnbWelcome`, plus the returning path
/// through `G.OnbSignIn` (which is `G.OnbAccount` in login mode).
///
/// Stated divergence: the tour draws over the REAL shell, and the shell is
/// the app layer's. So the tour stop is rendered by whatever the host passes
/// as `tour:` — this view owns when it runs, not what it covers.
public struct OnboardingFlowView<Tour: View, Shelf: View>: View {
    @State private var flow: OnboardingFlowModel
    private let anchorCatalog: [ShadeAnchorPicker.BrandEntry]
    private let payoff: (@Sendable (UUID) async throws -> PayoffEvidence)?
    /// The payoff's example shelf — the shelf's own bay, which is another
    /// feature's view, so the app draws it and hands it in (the same seam
    /// as `tour:`, for the same reason). `EmptyView` shows the words alone.
    private let exampleShelf: () -> Shelf
    private let shelfStarterCount: Int
    /// Absent, the handle step accepts anything and claims nothing — the same
    /// nil-means-unwired rule every other seam here follows. The app fills it.
    private let handleStore: OnbHandleStore?
    private let onScan: (() -> Void)?
    private let onImport: (() -> Void)?
    private let onSearch: (() -> Void)?
    private let tour: (_ onDone: @escaping () -> Void) -> Tour
    /// Onboarding is over. The app owns every destination; this hands one back.
    private let onFinished: (OnboardingFlowModel.Exit) -> Void

    public init(
        flow: OnboardingFlowModel,
        anchorCatalog: [ShadeAnchorPicker.BrandEntry],
        payoff: (@Sendable (UUID) async throws -> PayoffEvidence)? = nil,
        @ViewBuilder exampleShelf: @escaping () -> Shelf = { EmptyView() },
        shelfStarterCount: Int = 0,
        handleStore: OnbHandleStore? = nil,
        onScan: (() -> Void)? = nil,
        onImport: (() -> Void)? = nil,
        onSearch: (() -> Void)? = nil,
        @ViewBuilder tour: @escaping (_ onDone: @escaping () -> Void) -> Tour,
        onFinished: @escaping (OnboardingFlowModel.Exit) -> Void
    ) {
        _flow = State(initialValue: flow)
        self.anchorCatalog = anchorCatalog
        self.payoff = payoff
        self.exampleShelf = exampleShelf
        self.shelfStarterCount = shelfStarterCount
        self.handleStore = handleStore
        self.onScan = onScan
        self.onImport = onImport
        self.onSearch = onSearch
        self.tour = tour
        self.onFinished = onFinished
    }

    public var body: some View {
        stopBody
            .onChange(of: flow.exit) { _, exit in
                guard let exit else { return }
                onFinished(exit)
            }
    }

    @ViewBuilder private var stopBody: some View {
        switch flow.stop {
        case .hook:
            // Both returning doors are wired, so the login reveal exists.
            // Before the flow owned them the app passed neither, and the kit's
            // "or have an account? log in →" never rendered at all.
            OnbHookView(
                onCreateAccount: { flow.createAccount() },
                onAppleLogin: { flow.logInWithApple() },
                onPhoneLogin: { flow.logInWithPhone() }
            )
        case .quiz:
            OnbQuizView(
                model: flow.quiz,
                anchorCatalog: anchorCatalog,
                onExit: { flow.quizExited() },
                onFinished: { flow.quizFinished() }
            )
        case .payoff:
            // The anchor comes from the quiz or not at all — see
            // `OnboardingFlowModel.payoffAnchor`.
            OnbPayoffView(
                model: PayoffModel(anchor: flow.payoffAnchor, payoff: payoff),
                exampleShelf: exampleShelf,
                onBack: { flow.payoffBacked() },
                onContinue: { flow.payoffContinued() }
            )
            .id(flow.payoffAnchor?.variantID)
        case .account:
            if let account = flow.account {
                OnbAccountView(
                    model: account,
                    quiz: flow.quiz,
                    onExit: { flow.accountExited() },
                    onCreated: { flow.accountFinished() }
                )
                // A fresh walk on each arrival needs a fresh view identity —
                // `OnbAccountView` seeds its own `@State` from the model once.
                .id(ObjectIdentifier(account))
            }
        case .handle:
            OnbHandleView(
                model: OnbHandleModel(store: handleStore, suggestedFrom: flow.quiz.displayName),
                onClaimed: { flow.handleClaimed() }
            )
        case .shelfStarter:
            OnbBuildView(
                addedCount: shelfStarterCount,
                onScan: onScan,
                onImport: onImport,
                onSearch: onSearch,
                onSkip: { flow.shelfStarterFinished() }
            )
        case .tour:
            tour { flow.tourFinished() }
        case .welcome:
            OnbWelcomeView(
                buildLine: shelfStarterCount > 0
                    ? "pick up where you left off — "
                    + OnbBuildView.progressLine(added: shelfStarterCount)
                    : "search, scan, or create — your call",
                onBuild: { flow.welcomeChose(.buildShelf) },
                onImport: { flow.welcomeChose(.importList) },
                onBrowse: { flow.welcomeChose(.discover) }
            )
        }
    }
}
