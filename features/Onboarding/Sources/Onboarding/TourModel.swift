import Foundation
import Observation

/// The tour (`G.OnbTour`): two slides over the REAL app, not screenshots of
/// it — a scrim, a pop card, and a finger pointed at the tab the slide is
/// about. The words are here because they carry doctrine (no stars, every
/// claim shows its n) and deserve tests.
///
/// **First-onboarding only.** The tour runs once, at the end of a new
/// user's flow, between the shelf starter and the welcome. Returning users
/// never see it (the map's caption: "logging in skips all of it"), skip is
/// the same one-shot — skipping IS seeing it — and the seen marker is the
/// app's to keep (device-local: a reinstall may reshow the tour, which is
/// acceptable for a two-slide overlay and avoids a server flag for chrome).
@MainActor
@Observable
public final class TourModel {
    public struct Slide: Equatable, Sendable {
        /// The shell tab this slide points at, by the nav's own ids.
        public let tab: String
        public let title: String
        public let story: String
    }

    /// The kit's two slides, verbatim.
    public nonisolated static let slides: [Slide] = [
        Slide(
            tab: "shelf",
            title: "the face-off",
            story: "two products, one question: which do you reach for? "
                + "that\u{2019}s how your shelf ranks itself — no stars, ever."
        ),
        Slide(
            tab: "discover",
            title: "why we\u{2019}re here",
            story: "no ads, no bots, no gatekeeping. every claim shows its n, "
                + "and your shade is yours to say."
        )
    ]

    public private(set) var stepIndex = 0

    public init() {}

    public var slide: Slide {
        Self.slides[min(stepIndex, Self.slides.count - 1)]
    }

    public var isLastSlide: Bool {
        stepIndex >= Self.slides.count - 1
    }

    /// The next button's word: "next", then the kit's "take me in ✿".
    public var nextLabel: String {
        isLastSlide ? "take me in \u{273F}" : "next"
    }

    /// Advances, or says it is done — the caller owns what comes after
    /// (the welcome).
    public func next() -> Bool {
        guard !isLastSlide else { return false }
        stepIndex += 1
        return true
    }
}
