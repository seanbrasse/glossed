import DataKit
import DesignSystem
import Foundation
import Observation
import Tracking

/// The quiz's state machine (GLO-18, `G.OnbQuiz`): three steps, one of them
/// a conditional branch — hair only if haircare was picked. The step list
/// is recomputed from the answers live, exactly as the kit does it, so
/// picking haircare mid-flight grows the flow and unpicking it shrinks it.
///
/// **The foundation question left the quiz (Sean, Sep 2).** PRD §06 led
/// with "what foundation do you wear?" because an exact shade beats a tone
/// band. It does — when the shade is there to pick. GLO-269 records that
/// the catalog behind that question has 4 shade rows of 9,019, so the
/// question mostly ended in "not listed", and Sean's ruling names the cost:
/// *"we don't want users to not find their product and get a distaste for
/// the app."* So the tone palette is asked always, the foundation is asked
/// where the bottle is in hand (logging one IS naming the anchor —
/// `user_shade_anchor` is a view over anchor-category items), and undertone
/// is not asked at all: self-report is unreliable there (the wrist-vein
/// test fails olive skin outright), and the app already learns it from fit
/// answers on the undertone axis, which domain.md says win over any prior.
/// Skin type, concerns and brands still come after signup.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: String, Equatable {
        case domains, tone, hair
    }

    /// The kit's default: makeup + skincare pre-selected — the two most
    /// shopped halves, not an empty ask.
    public private(set) var domains: [Domain] = [.makeup, .skincare]
    /// The seam the payoff reads (`OnboardingFlowModel.payoffAnchor`).
    /// **Nothing in the quiz sets it any more** — the foundation question
    /// is gone (see the type comment) — so the payoff runs its neutral
    /// path by construction. Kept rather than ripped out because the flow,
    /// the app and the debug catalog all hold the other end of this seam,
    /// and the follow-up that feeds it from the shelf starter (or removes
    /// it) is a change to those files, not to the quiz.
    public var anchor = ShadeAnchorPicker.Selection() {
        didSet {
            if anchor.shade != nil {
                noFoundation = false
            }
        }
    }

    public private(set) var noFoundation = false
    public var hairPattern: String?
    /// 0-based palette index; the wire tone band is this + 1 — the mapping
    /// lives in `draft(birthYearMonth:)` and nowhere else.
    public var toneIndex: Int?
    public private(set) var stepIndex = 0

    private let tracker: Tracker?
    /// The last step this model reported viewing, so a re-render is not a
    /// second impression.
    private var viewedStep: Step?

    public init(tracker: Tracker? = nil) {
        self.tracker = tracker
    }

    // MARK: - the step list, derived

    /// Recomputed from the answers, never stored: a stored list is one
    /// mid-flight domain change away from disagreeing with its predicates.
    /// Tone is unconditional now; hair is the one branch left.
    public var steps: [Step] {
        var list: [Step] = [.domains, .tone]
        if domains.contains(.haircare) {
            list.append(.hair)
        }
        return list
    }

    public var step: Step {
        let list = steps
        return list[min(stepIndex, list.count - 1)]
    }

    public var isFirstStep: Bool {
        stepIndex == 0
    }

    /// True when `next()` would leave the quiz — the caller owns what comes
    /// after (the payoff, in its own PR).
    public var isLastStep: Bool {
        stepIndex >= steps.count - 1
    }

    public func next() -> Bool {
        recordCompleted(step)
        guard !isLastStep else { return false }
        stepIndex += 1
        return true
    }

    public func back() {
        stepIndex = max(0, stepIndex - 1)
    }

    // MARK: - answers

    /// The quiz never lets the last domain deselect — an empty domains list
    /// would render an empty app (the Segmented multi rule, same invariant).
    public func toggle(_ domain: Domain) {
        if domains.contains(domain) {
            guard domains.count > 1 else { return }
            domains.removeAll { $0 == domain }
        } else {
            domains.append(domain)
        }
        clampStep()
    }

    public func selectAllDomains() {
        domains = Domain.allCases
    }

    /// "i don't wear any foundation" — clears the anchor; picking a shade
    /// later clears it back (the two are exclusive answers to one question).
    /// No screen asks it since Sep 2; the payoff still honours it.
    public func setNoFoundation() {
        noFoundation = true
        anchor = ShadeAnchorPicker.Selection()
    }

    private func clampStep() {
        stepIndex = min(stepIndex, steps.count - 1)
    }

    // MARK: - the words (tested, because they carry rules)

    public nonisolated static func question(for step: Step) -> [String] {
        switch step {
        case .domains: ["what do", "you buy?"]
        case .tone: ["where\u{2019}s your", "skin tone?"]
        case .hair: ["what\u{2019}s your", "hair type?"]
        }
    }

    public nonisolated static func aside(for step: Step) -> String {
        switch step {
        case .domains: "pick every one you shop for — this sets which halves of the app lead"
        case .tone: "closest is close enough — logging your foundation sharpens it later"
        case .hair: "only asked because you buy haircare"
        }
    }

    /// The kit's ten-swatch palette, weighted toward the deep range on
    /// purpose (PRD §06: five bands for the entire deep half is a trust
    /// problem, not just a precision one).
    public nonisolated static let toneSwatches: [UInt32] = [
        0xF6EDE4, 0xF3E7DB, 0xF7EAD0, 0xEADABA, 0xD7BD96,
        0xC9A175, 0xA07E56, 0x825C43, 0x604134, 0x3A312A
    ]

    // MARK: - what the quiz hands the account step

    /// The prior, assembled: the account step supplies the birthday and
    /// writes the whole draft in one batch (the ticket's PR 3). The 0-based
    /// palette index becomes the 1-based tone band HERE and nowhere else.
    /// What the app calls you. Collected at the account stage, not here, but
    /// it rides the same `ProfileDraft` so the whole prior lands in ONE write
    /// — which is also why it cannot be collected after `createAccount`.
    ///
    /// **Nothing derived a handle from it and nothing should.** A handle is an
    /// identifier (GLO-191); a name is moderated text. Suggesting one from the
    /// other is a convenience, and the suggestion is made on the handle screen
    /// where the user still confirms it — a generated identity nobody chose is
    /// not the same thing as a generated suggestion.
    public var displayName = ""

    public func draft(birthYearMonth: String) -> ProfileDraft {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProfileDraft(
            birthYearMonth: birthYearMonth,
            domains: domains,
            toneBand: toneIndex.map { $0 + 1 },
            hairPattern: hairPattern,
            // Empty means "not given", not "cleared": `saveProfile` upserts and
            // a nil column leaves the old value standing, which is the rule
            // `DisplayNameView` already documents.
            displayName: name.isEmpty ? nil : name
        )
    }

    // MARK: - events

    /// One impression per step actually reached — a re-render of the same
    /// step is not a second view (tech/06's dwell rule: never per frame).
    public func recordViewed() {
        let current = step
        guard viewedStep != current, let tracker else {
            viewedStep = step
            return
        }
        viewedStep = current
        Task { await tracker.track(.onbStepViewed(step: current.rawValue, branch: Self.branch(of: current))) }
    }

    private func recordCompleted(_ step: Step) {
        guard let tracker else { return }
        Task { await tracker.track(.onbStepCompleted(step: step.rawValue, branch: Self.branch(of: step))) }
    }

    /// tech/06's branch vocabulary. Tone keeps its `palette` branch name
    /// even though it is no longer conditional — the event stream's
    /// vocabulary does not change because the step's predicate did.
    nonisolated static func branch(of step: Step) -> OnboardingBranch? {
        switch step {
        case .hair: .hair
        case .tone: .palette
        case .domains: nil
        }
    }
}
