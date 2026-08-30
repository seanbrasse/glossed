import DataKit
import DesignSystem
import Foundation
import Observation
import Tracking

/// The quiz's state machine (GLO-18, `G.OnbQuiz`): four steps, two of them
/// conditional branches — hair only if haircare was picked, the tone
/// palette only if there is no foundation to anchor on. The step list is
/// recomputed from the answers live, exactly as the kit does it, so picking
/// haircare mid-flight grows the flow and unpicking it shrinks it.
///
/// The ordering is PRD §06's whole point: the anchor question leads because
/// "what foundation do you wear?" is the easiest question in the flow and
/// produces strictly better data than a tone palette. Skin type, concerns
/// and brands deliberately come after signup.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: String, Equatable {
        case domains, anchor, hair, tone
    }

    /// The kit's default: makeup + skincare pre-selected — the two most
    /// shopped halves, not an empty ask.
    public private(set) var domains: [Domain] = [.makeup, .skincare]
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
    public var steps: [Step] {
        var list: [Step] = [.domains, .anchor]
        if domains.contains(.haircare) {
            list.append(.hair)
        }
        if noFoundation {
            list.append(.tone)
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

    /// "i don't wear any foundation" — clears the anchor and adds the tone
    /// step; picking a shade later clears it back (the two are exclusive
    /// answers to one question).
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
        case .anchor: ["what foundation", "do you wear?"]
        case .hair: ["what\u{2019}s your", "hair type?"]
        case .tone: ["where\u{2019}s your", "skin tone?"]
        }
    }

    public nonisolated static func aside(for step: Step) -> String {
        switch step {
        case .domains: "pick every one you shop for — this sets which halves of the app lead"
        case .anchor: "your exact shade is the anchor — it beats a tone band every time"
        case .hair: "only asked because you buy haircare"
        case .tone: "closest is close enough — change it any time"
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
    public func draft(birthYearMonth: String) -> ProfileDraft {
        ProfileDraft(
            birthYearMonth: birthYearMonth,
            domains: domains,
            toneBand: toneIndex.map { $0 + 1 },
            hairPattern: hairPattern
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

    /// tech/06's branch vocabulary: the two conditional steps name their
    /// branch; the two unconditional ones carry none.
    nonisolated static func branch(of step: Step) -> OnboardingBranch? {
        switch step {
        case .hair: .hair
        case .tone: .palette
        case .domains, .anchor: nil
        }
    }
}
