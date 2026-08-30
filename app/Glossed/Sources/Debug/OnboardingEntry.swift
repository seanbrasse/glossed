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
        private static func swatch(_ value: UInt32) -> Color {
            Color(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: 1
            )
        }

        /// The kit's own foundation fixture (`G.OnbQuiz`), so the anchor step
        /// renders the picker in the shape the frame shows. The live catalog
        /// read arrives with the account PR's wiring.
        static let fixtureCatalog: [ShadeAnchorPicker.BrandEntry] = [
            .init(brand: "fenty beauty", products: [
                .init(name: "pro filt'r soft matte", shades: [
                    .init(code: "220", hex: swatch(0xE0B891), tone: 5, n: 31),
                    .init(code: "240", hex: swatch(0xD9A87E), tone: 6, n: 12),
                    .init(code: "290", hex: swatch(0xC08B5E), tone: 7, n: 24),
                    .init(code: "330", hex: swatch(0x8C5E3C), tone: 9, n: 9)
                ])
            ]),
            .init(brand: "rare beauty", products: [
                .init(name: "liquid touch weightless", shades: [
                    .init(code: "21n", hex: swatch(0xE8C4A0), tone: 4, n: 6),
                    .init(code: "23w", hex: swatch(0xDCA97F), tone: 6, n: 7),
                    .init(code: "26w", hex: swatch(0xCC9668), tone: 7, n: 11),
                    .init(code: "31c", hex: swatch(0xA87A54), tone: 8, n: 5)
                ])
            ]),
            .init(brand: "nars", products: [
                .init(name: "light reflecting foundation", shades: [
                    .init(code: "mont blanc", hex: swatch(0xEBD3B8), tone: 3, n: 8),
                    .init(code: "punjab", hex: swatch(0xCFA37C), tone: 6, n: 5),
                    .init(code: "barcelona", hex: swatch(0xA87A54), tone: 8, n: 14)
                ]),
                .init(name: "soft matte concealer", shades: [
                    .init(code: "custard", hex: swatch(0xE7C49C), tone: 4, n: 6),
                    .init(code: "ginger", hex: swatch(0xD6A67C), tone: 6, n: 4)
                ])
            ]),
            .init(brand: "estée lauder", products: [
                .init(name: "double wear", shades: [
                    .init(code: "2c2", hex: swatch(0xE6C6A4), tone: 4, n: 9),
                    .init(code: "3w1", hex: swatch(0xD8AA7C), tone: 6, n: 17),
                    .init(code: "4n1", hex: swatch(0xBD8B5E), tone: 7, n: 7)
                ])
            ])
        ]

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
                            .init(id: "discover", label: "discover", systemImage: "sparkles"),
                            .init(id: "shelf", label: "shelf", systemImage: "square.split.1x2"),
                            .init(id: "you", label: "you", systemImage: "person.crop.circle")
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
                case hook, quiz, payoff, account, welcome
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
                        onCreated: { stop = .welcome }
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
