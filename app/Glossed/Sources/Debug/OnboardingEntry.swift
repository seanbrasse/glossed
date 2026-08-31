#if DEBUG

    import DataKit
    import DesignSystem
    import Onboarding
    import SwiftUI

    /// Its own file for the same reason `LiveShelfEntry` is: `ScreenEntries`
    /// sits at SwiftLint's file-length ceiling.
    ///
    /// The flow entry hosts hook → quiz as a real transition (the GLO-180
    /// lesson: entries that construct a view directly test the view, not the
    /// flow, and every ladder transition was undrivable for months because of
    /// exactly that). The app's real entry cannot host onboarding yet — the
    /// dev shell auto-signs-in as maya, and putting the hook in front of that
    /// would break every lane's drives — so this door is where the flow
    /// lives until the account PR wires the real one.
    @MainActor
    enum OnboardingEntry {
        /// The anchor fixture moved to `App/OnboardingAnchorCatalog.swift` when
        /// the real shell started mounting FLOW 1 (GLO-245). One copy, so the
        /// debug door and the app cannot drift apart — and the reason it is a
        /// fixture at all is written there.
        static let fixtureCatalog = OnboardingAnchorCatalog.entries

        static let wholeTrip = ScreenEntry(
            id: "onb-whole-trip",
            title: "onboarding · the whole trip",
            note: "hook → quiz, the real transition. pick haircare and the flow grows a step; "
                + "say no foundation and the tone palette joins — the branches are the point"
        ) {
            OnboardingTrip()
        }

        static let quizAnchor = ScreenEntry(
            id: "onb-quiz-anchor",
            title: "onboarding · the anchor question",
            note: "the picker mid-quiz: brand → shade with its n, band-filtered, 'not listed' as a "
                + "peer, and the no-foundation door that swaps the question rather than dead-ending"
        ) {
            OnbQuizView(
                model: {
                    let model = OnboardingModel()
                    _ = model.next()
                    return model
                }(),
                anchorCatalog: fixtureCatalog,
                onFinished: {}
            )
        }

        static let tour = ScreenEntry(
            id: "onb-tour",
            title: "onboarding · the tour",
            note: "two slides over a stand-in shell — scrim, pop card, and the finger on the tab. "
                + "first-onboarding only; returning users and reruns never see it (the app owns the marker)"
        ) {
            TourHost()
        }

        static let welcome = ScreenEntry(
            id: "onb-welcome",
            title: "onboarding · welcome in",
            note: "three doors, all real destinations — and the honest footer about why finding "
                + "friends is not one of them"
        ) {
            OnbWelcomeView(onBuild: {}, onImport: {}, onBrowse: {})
        }

        /// A stand-in shell for the overlay: milk ground + a real FloatingNav,
        /// so the finger points at actual tabs. The real mount (over the live
        /// shell, first onboarding only) arrives with the account PR.
        private struct TourHost: View {
            @State private var tab = "shelf"
            @State private var done = false

            var body: some View {
                ZStack(alignment: .bottom) {
                    Tokens.Ground.milk.ignoresSafeArea()
                    Text(done ? "tour done → welcome" : "the app would be here")
                        .meta()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    FloatingNav(
                        tabs: [
                            .init(id: "discover", label: "discover", glyph: .discover),
                            .init(id: "shelf", label: "shelf", glyph: .shelf),
                            .init(id: "you", label: "you", glyph: .avatar(name: "maya"))
                        ],
                        active: $tab,
                        onPlus: {}
                    )
                    .padding(.bottom, Tokens.Space.s3)
                    if !done {
                        TourOverlay(
                            model: TourModel(),
                            // Fixture anchors, read off the stand-in nav's
                            // own tab centers — the shell computes real ones.
                            anchorX: { $0 == "shelf" ? 175 : 112 },
                            onTabChange: { tab = $0 },
                            onDone: { done = true }
                        )
                    }
                }
            }
        }

        private struct OnboardingTrip: View {
            private enum Stop {
                case hook, quiz, payoff, account, build, welcome
            }

            @State private var stop = Stop.hook
            /// One quiz for the whole trip: the account stage batch-writes
            /// ITS answers, so the two must share state.
            @State private var quiz = OnboardingModel()

            var body: some View {
                switch stop {
                case .hook:
                    OnbHookView(onCreateAccount: {
                        quiz = OnboardingModel()
                        stop = .quiz
                    })
                case .quiz:
                    OnbQuizView(
                        model: quiz,
                        anchorCatalog: OnboardingEntry.fixtureCatalog,
                        onFinished: { stop = .payoff }
                    )
                case .payoff:
                    // A backed fixture — the neutral gate's sides are unit
                    // tested; the trip shows the claim the frame shows.
                    OnbPayoffView(
                        model: PayoffModel(
                            anchor: .init(brand: "fenty beauty", shadeCode: "240", variantID: UUID()),
                            payoff: { _ in
                                PayoffEvidence(exactShadeCount: 12, withFitCount: 9, evidenceBacked: true)
                            }
                        ),
                        onContinue: { stop = .account }
                    )
                case .account:
                    // Stubbed finish: the fixture trip writes nothing — the
                    // live batch write drives with the real wiring.
                    OnbAccountView(
                        model: AccountModel(store: AccountStore(finish: { _ in })),
                        quiz: quiz,
                        onExit: { stop = .payoff },
                        onCreated: { stop = .build }
                    )
                case .build:
                    // Doors are fixture no-ops here; only ones the trip can
                    // "wire" render — snap-a-photo stays nil (no flow exists)
                    // and correctly does not appear.
                    OnbBuildView(
                        addedCount: 2,
                        onScan: {},
                        onImport: {},
                        onSearch: {},
                        onSkip: { stop = .welcome }
                    )
                case .welcome:
                    OnbWelcomeView(
                        onBuild: { stop = .hook },
                        onImport: { stop = .hook },
                        onBrowse: { stop = .hook }
                    )
                }
            }
        }
    }

#endif
