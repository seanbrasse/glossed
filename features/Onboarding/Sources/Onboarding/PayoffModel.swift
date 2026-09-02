import DataKit
import Foundation
import Observation
import Tracking

/// The payoff's one rule, PRD §06·6, is a GATE and not a rendering choice:
/// **evidence-backed or it does not run.** One weak early recommendation
/// poisons every good one after it — so when the claim cannot be made, the
/// screen shows the neutral fallback and says nothing about matches. The
/// discriminator is the RPC's own `evidenceBacked`, never a client count
/// check (the leaderboard's nulled-claim doctrine at this screen).
@MainActor
@Observable
public final class PayoffModel {
    public enum Phase: Equatable {
        case loading
        /// The claim, with its numbers — only ever entered on the RPC's word.
        case backed(PayoffEvidence)
        /// No anchor, thin evidence, or a failed read — all one honest state.
        case neutral

        /// PayoffEvidence is not Equatable in DataKit (frozen) — compared by
        /// its three fields here rather than conformed retroactively.
        public static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.neutral, .neutral):
                true
            case let (.backed(left), .backed(right)):
                left.exactShadeCount == right.exactShadeCount
                    && left.withFitCount == right.withFitCount
                    && left.evidenceBacked == right.evidenceBacked
            default:
                false
            }
        }
    }

    /// What the quiz knew about the anchor, for the badge's words. Nil
    /// variantID (no anchor, "not listed", no foundation) is neutral by
    /// construction — there is nothing to ask the RPC about.
    public struct Anchor: Equatable, Sendable {
        public let brand: String
        public let shadeCode: String
        public let variantID: UUID?

        public init(brand: String, shadeCode: String, variantID: UUID?) {
            self.brand = brand
            self.shadeCode = shadeCode
            self.variantID = variantID
        }
    }

    /// One product on the example shelf. `nUsers` is the number of people
    /// who rank it — present when the pick came from the leaderboard, nil
    /// when it is a catalog stand-in. The screen's eyebrow reads off that:
    /// a shelf where every tile carries its n is "what people are logging";
    /// one where any tile does not is "a shelf, for example". A count is a
    /// claim and a claim carries its n; a stand-in claims nothing.
    public struct ShelfPick: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let brand: String
        public let name: String
        public let categorySlug: String
        public let imageURL: URL?
        public let nUsers: Int?

        public init(
            id: UUID, brand: String, name: String, categorySlug: String,
            imageURL: URL? = nil, nUsers: Int? = nil
        ) {
            self.id = id
            self.brand = brand
            self.name = name
            self.categorySlug = categorySlug
            self.imageURL = imageURL
            self.nUsers = nUsers
        }
    }

    public private(set) var phase: Phase = .loading
    public let anchor: Anchor?
    /// The example shelf (Sean, Sep 2: *"show an example shelf full of
    /// popular products and be like build your shelf"*). Empty until the
    /// seam answers; empty forever if it fails or was never wired — the
    /// screen then shows the words alone, which is still a true screen.
    public private(set) var shelf: [ShelfPick] = []

    private let payoff: (@Sendable (UUID) async throws -> PayoffEvidence)?
    private let sampleShelf: (@Sendable () async throws -> [ShelfPick])?
    private let tracker: Tracker?
    var loadTask: Task<Void, Never>?
    var shelfTask: Task<Void, Never>?

    public init(
        anchor: Anchor?,
        payoff: (@Sendable (UUID) async throws -> PayoffEvidence)? = nil,
        sampleShelf: (@Sendable () async throws -> [ShelfPick])? = nil,
        tracker: Tracker? = nil
    ) {
        self.anchor = anchor
        self.payoff = payoff
        self.sampleShelf = sampleShelf
        self.tracker = tracker
    }

    /// Every tile carries its n, so the shelf may be called what people are
    /// logging. Any tile without one makes the whole shelf an example.
    public var shelfIsRanked: Bool {
        !shelf.isEmpty && shelf.allSatisfy { $0.nUsers != nil }
    }

    public func load() {
        loadShelf()
        loadTask?.cancel()
        guard let payoff, let variantID = anchor?.variantID else {
            resolve(.neutral, evidence: nil)
            return
        }
        phase = .loading
        loadTask = Task {
            let evidence = try? await payoff(variantID)
            guard !Task.isCancelled else { return }
            // The gate: the RPC's word, not a count comparison here.
            if let evidence, evidence.evidenceBacked {
                resolve(.backed(evidence), evidence: evidence)
            } else {
                resolve(.neutral, evidence: evidence)
            }
        }
    }

    private func loadShelf() {
        shelfTask?.cancel()
        guard let sampleShelf else { return }
        shelfTask = Task {
            let picks = await (try? sampleShelf()) ?? []
            guard !Task.isCancelled else { return }
            shelf = picks
        }
    }

    private func resolve(_ phase: Phase, evidence: PayoffEvidence?) {
        self.phase = phase
        guard let tracker else { return }
        let count = evidence?.exactShadeCount ?? 0
        let backed = if case .backed = phase {
            true
        } else {
            false
        }
        Task { await tracker.track(.onbPayoffShown(exactShadeCount: count, evidenceBacked: backed)) }
    }

    // MARK: - the words

    /// "12 people wear / your exact shade" — the headline only a backed
    /// phase may render.
    public nonisolated static func headline(exactShadeCount: Int) -> String {
        "\(exactShadeCount) people wear\nyour exact shade"
    }

    /// "fenty beauty 240 · your anchor"
    public nonisolated static func anchorBadge(_ anchor: Anchor) -> String {
        "\(anchor.brand) \(anchor.shadeCode) · your anchor"
    }

    /// The receipt under the claim: where the number comes from.
    public nonisolated static let evidenceLabel =
        "of them logged how the shade fit — that\u{2019}s where this comes from"

    /// The kit's footer, with the anchor's own words in it.
    public nonisolated static func footerLine(_ anchor: Anchor) -> String {
        "no tone bands, no averages — these are people in \(anchor.brand) \(anchor.shadeCode)"
    }

    /// The example shelf's eyebrow: a claim when every tile has its n, a
    /// labelled example otherwise.
    public nonisolated static func shelfEyebrow(isRanked: Bool) -> String {
        isRanked ? "WHAT PEOPLE ARE LOGGING" : "A SHELF, FOR EXAMPLE"
    }

    /// Under a tile: its n, or nothing. Never a made-up number.
    public nonisolated static func shelfLine(_ pick: ShelfPick) -> String? {
        pick.nUsers.map { "\($0) rank it" }
    }
}
