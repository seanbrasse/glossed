import DataKit
import DesignSystem
import Onboarding
import SwiftUI

// FLOW 1, mounted (GLO-245) — its own file for the reason `AppShellRoutine` and
// `AppShellCollections` are: `AppShell.swift` sits at SwiftLint's 300-line
// ceiling, so a new surface extracts rather than accretes.

extension AppShell {
    /// **`OnboardingFlowView` was constructed by nothing.** Not by the app, and
    /// not — despite what the handoff said — by the debug picker either: that
    /// door hosts `OnbHookView` and a hand-rolled `OnboardingTrip`, which is
    /// screens rather than the flow. `OnboardingFlowModel` appeared only in its
    /// own tests. #383 made FLOW 1 a real flow and nothing could reach it.
    ///
    /// Every seam below is live except the anchor catalog, and that one is a
    /// catalog gap rather than a shortcut — see `OnboardingAnchorCatalog`.
    ///
    /// Sean, Aug 31: *"just ignore auth for now, we will have the flows for
    /// before and after and I will wire it in later."* So the account step runs
    /// on `AccountStore`'s stubbed `sendCode` / `verifyCode` (GLO-23 owns the
    /// real ones) while its `finish` is the REAL profile write — the quiz's
    /// answers land in `profiles`, which is also what makes `needsOnboarding`
    /// go false. Swapping the stubs later changes nothing here.
    @ViewBuilder var onboardingFlow: some View {
        if let client = session.client {
            OnboardingFlowView(
                flow: OnboardingFlowModel(
                    store: .repository(ProfileRepository(client: client)),
                    resolveVariant: { brand, product, shade in
                        session.resolveAnchorVariant(brand: brand, product: product, shade: shade)
                    }
                ),
                anchorCatalog: OnboardingAnchorCatalog.entries,
                // The first receipt the app ever shows, and it is a real one:
                // `payoff` reads the aggregate for the variant just chosen. An
                // anchor that did not resolve hands nil and the screen says it
                // has nothing yet, which is true.
                payoff: { try await AggregatesRepository(client: client).payoff(variantID: $0) },
                shelfStarterCount: session.shelfItemCount,
                // Sean, Aug 31: "Users shouldn't make it through onboarding
                // without a username/handle." Same two calls `HandleClaimView`
                // uses from the profile — one seam, one server rule, two
                // entrances.
                handleStore: OnbHandleStore(
                    isAvailable: { try await SocialRepository(client: client).handleAvailable($0) },
                    claim: { try await SocialRepository(client: client).claimHandle($0) }
                ),
                // The three doors `OnbBuildView` offers, wired to what the app
                // actually has. `import` is the notice the drawer gives, for
                // the same reason: `ImportParsing` has no live conformance.
                onScan: { ladderTrip = UUID(); ladderOpen = true },
                onImport: { notice = "import needs the catalog parser — GLO-19" },
                onSearch: { ladderTrip = UUID(); ladderOpen = true },
                tour: { onDone in tourOverTheShell(onDone: onDone) },
                onFinished: { exit in finishOnboarding(exit) }
            )
        }
    }

    /// The tour draws over the REAL shell — the stated divergence
    /// `OnboardingFlowView` documents, and the reason `tour:` is a closure the
    /// host fills rather than a view the feature owns.
    func tourOverTheShell(onDone: @escaping () -> Void) -> some View {
        tabs.overlay {
            TourOverlay(
                model: TourModel(),
                anchorX: navAnchorX,
                onTabChange: { named in
                    guard let picked = ShellTab(rawValue: named) else { return }
                    tab = picked
                },
                onDone: onDone
            )
        }
    }

    /// Where a tour slide's pointer lands — the nav's own answer, keyed by the
    /// tab label the slide names.
    ///
    /// Nil before the nav has been laid out, and `TourOverlay` draws no pointer
    /// for nil rather than one in the wrong place. An earlier version of this
    /// computed thirds of the nav's frame and put the arrow between `shelf` and
    /// `you` — visibly, on the simulator — because that frame includes the `+`.
    func navAnchorX(for named: String) -> CGFloat? {
        navTabAnchors[named]
    }

    /// Onboarding is over. The app owns every destination — the flow hands one
    /// back and routes nothing itself.
    func finishOnboarding(_ exit: OnboardingFlowModel.Exit) {
        switch exit {
        case .discover:
            tab = .discover
        case .buildShelf:
            tab = .shelf
            ladderTrip = UUID()
            ladderOpen = true
        case .importList:
            tab = .shelf
            notice = "import needs the catalog parser — GLO-19"
        }
        Task { await session.onboardingFinished() }
    }
}
