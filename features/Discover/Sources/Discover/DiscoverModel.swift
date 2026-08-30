import DataKit
import DesignSystem
import Foundation
import Observation
import Tracking

/// The discover tab's state (GLO-20). One load, two sections, and the copy
/// for every basis — kept here rather than in the view because the words
/// carry the evidence rules and deserve tests.
@MainActor
@Observable
public final class DiscoverModel {
    public enum Phase: Equatable {
        case loading
        /// Nothing above min-n anywhere and nothing to wander to — the view
        /// still renders (never blank), this just names the state.
        case empty
        case loaded
    }

    public private(set) var phase: Phase = .loading
    public private(set) var picks: [DiscoverHit] = []
    public private(set) var crosswalk: [CrosswalkHit] = []
    /// Category slug → the catalog's own label, for the frame's per-cell
    /// eyebrow (GLO-226). Empty until the read lands, and empty forever when
    /// the store supplies no `categories` — either way the eyebrow simply
    /// does not render, which is the correct degrade for a label we could
    /// only otherwise invent.
    private var categoryLabels: [String: String] = [:]

    /// One card in the feed's stream. The surface is a single scroll of
    /// mixed, self-labeling kinds (GLO-195: discovery is incorporated into
    /// the feed — "we are not a store") — a sectioned page of product cards
    /// is a catalog layout, and the section header was doing the labeling
    /// work each card's basis line already does better.
    ///
    /// Look posts join this enum in GLO-196; the composition below is the
    /// architecture they interleave into.
    public enum StreamCard: Identifiable {
        case pick(DiscoverHit)
        /// One card holding all partner rows — the crosswalk is one thought.
        case crosswalk([CrosswalkHit])
        /// The way to trending, as a card IN the stream rather than a header
        /// link: a stream has no headers to hang a link on, and a card can
        /// say what is behind it. It makes no claim and carries no n; the
        /// view drops it when the app wires no destination (the full-page
        /// rule — an affordance that leads nowhere is not offered).
        case trendingTeaser
        /// A card the APP built and injected (GLO-200). Features never import
        /// features, so a look post or the tune card cannot be a case here —
        /// the app composes them and the stream only knows an identity and a
        /// place. Same wall FitPromptCard hit, same answer.
        case injected(id: String)

        public var id: String {
            switch self {
            case let .pick(hit): "pick-\(hit.id)"
            case .crosswalk: "crosswalk"
            case .trendingTeaser: "trending"
            case let .injected(id): "injected-\(id)"
            }
        }
    }

    /// An app-supplied card and where it goes. `position` indexes into the
    /// stream AFTER the built-in insertions, and injection order is by
    /// ascending position then id — deterministic, like everything else in
    /// the composition (GLO-195's rule extends, not bends).
    public struct InjectedCard: Identifiable, Sendable {
        public let id: String
        public let position: Int

        public init(id: String, position: Int) {
            self.id = id
            self.position = position
        }
    }

    /// Set by the app shell; the model re-composes on change.
    public var injectedCards: [InjectedCard] = []

    /// The stream, composed deterministically — no randomness, so the order
    /// is testable and two loads of the same data read the same.
    ///
    /// Picks keep the SERVER's order untouched: 0040 ranks them and the
    /// client does not second-guess it. The crosswalk lands after the second
    /// pick — early enough to be part of the feed's opening, late enough
    /// that the top of the stream is picks about *you*. Trending lands after
    /// the fifth, where the stream turns from "for you" toward "everyone".
    /// Short streams degrade by appending: every card still appears.
    public var stream: [StreamCard] {
        var cards: [StreamCard] = picks.map { .pick($0) }
        if !crosswalk.isEmpty {
            cards.insert(.crosswalk(crosswalk), at: min(2, cards.count))
        }
        cards.insert(.trendingTeaser, at: min(6, cards.count))
        // Ascending position, DESCENDING id within a position: each insert
        // displaces the previously-inserted tie rightward, so ascending ids
        // come out in order and a card's position is its final index.
        let ordered = injectedCards.sorted {
            ($0.position, $1.id) < ($1.position, $0.id)
        }
        for injected in ordered {
            cards.insert(.injected(id: injected.id), at: min(injected.position, cards.count))
        }
        return cards
    }

    /// Which board the `leaderboards →` door opens at — `G.Discover` links
    /// to `G.Leaderboard` without naming a category, and `LeaderboardModel`
    /// needs one, so the stream supplies it rather than the client inventing
    /// a favourite. The board carries its own category pills, so landing
    /// anywhere is one tap from anywhere else.
    ///
    /// The **first claiming pick**, never the wander: the wander is a
    /// deliberate random, and opening the boards on a category the engine
    /// picked at random would be arbitrary where every other number on this
    /// screen is earned. Nil when nothing was picked — and the view drops
    /// the link then, because an affordance that leads nowhere is not
    /// offered (the trending teaser's rule, the same one).
    public var leaderboardEntry: CatalogHit? {
        picks.first { $0.basis != .exploration }?.hit
    }

    private let store: DiscoverStore?
    private let imageBase: URL?
    private let tracker: Tracker?
    var loadTask: Task<Void, Never>?

    public init(store: DiscoverStore?, imageBase: URL? = nil, tracker: Tracker? = nil) {
        self.store = store
        self.imageBase = imageBase
        self.tracker = tracker
    }

    public func load() {
        loadTask?.cancel()
        guard let store else {
            phase = .empty
            return
        }
        phase = .loading
        loadTask = Task {
            // The two reads fail independently on purpose: a crosswalk
            // hiccup must not blank the picks, nor the reverse.
            async let feed = try? store.feed(12)
            async let partners = try? store.crosswalk(6)
            // Reference data, and the third read that must not blank the
            // other two: a categories hiccup costs the eyebrow, nothing else.
            async let labels = Self.labels(from: store)
            let (loadedPicks, loadedPartners, loadedLabels) = await (feed, partners, labels)
            guard !Task.isCancelled else { return }
            picks = loadedPicks ?? []
            crosswalk = loadedPartners ?? []
            categoryLabels = loadedLabels
            phase = picks.isEmpty && crosswalk.isEmpty ? .empty : .loaded
            recordImpressions()
        }
    }

    /// One categories read, folded to the slug → label map the eyebrow needs.
    /// A store with no `categories` returns empty, and so does a failure —
    /// the eyebrow is chrome, and chrome never costs the screen its picks.
    private nonisolated static func labels(from store: DiscoverStore) async -> [String: String] {
        guard let read = store.categories, let rows = try? await read() else { return [:] }
        return Dictionary(rows.map { ($0.slug, $0.label) }, uniquingKeysWith: { first, _ in first })
    }

    /// `G.Discover`'s per-cell `<Eyebrow>{c.type}</Eyebrow>` — `CREAM BLUSH`
    /// over the name. The catalog's own label, never a slug dressed up as
    /// one; `Text.eyebrow()` does the uppercasing, so the words stay
    /// lowercase everywhere they are stored and read.
    ///
    /// Nil for a slug the read did not cover, which is the same rule the
    /// trending teaser and the leaderboards door already follow: the element
    /// is absent rather than wrong.
    public func categoryEyebrow(for hit: CatalogHit) -> String? {
        categoryLabels[hit.categorySlug]
    }

    /// The basis line under each pick — lowercase, owner's words, and every
    /// claim names whose n it is (domain.md §5: a cohort claim never renders
    /// ambiguously). Exploration claims nothing, and says so.
    public nonisolated static func basisLine(_ basis: DiscoverHit.Basis) -> String {
        switch basis {
        case .taste: "your taste"
        case .shade: "your shade"
        case .everyone: "everyone"
        case .popular: "people keep this"
        case .exploration: "a wander"
        }
    }

    /// What the basis n counts, for the EvidenceLine label. Nil means the
    /// row makes no claim (exploration) and renders no n at all — a zero
    /// would read as a failed claim rather than the absence of one.
    public nonisolated static func evidenceLabel(_ basis: DiscoverHit.Basis) -> String? {
        switch basis {
        case .taste: "of your logs"
        case .shade: "face-offs · your shade"
        case .everyone: "face-offs · everyone"
        case .popular: "people"
        case .exploration: nil
        }
    }

    /// tech/06's slot vocabulary, from the basis: Stage 1 rows are `picked`,
    /// the population tiers are `stage0`, and the wander names itself. The
    /// crosswalk's rows carry their own slot at the call site.
    public nonisolated static func slot(for basis: DiscoverHit.Basis) -> RecSlot {
        switch basis {
        case .taste: .picked
        case .shade, .everyone, .popular: .stage0
        case .exploration: .exploration
        }
    }

    /// One impression per row actually shown, fired when a load lands — not
    /// per scroll, not per frame; dwell is never a signal here (tech/06).
    private func recordImpressions() {
        guard let tracker else { return }
        let picked = picks
        let partners = crosswalk
        Task {
            for pick in picked {
                await tracker.track(.recImpression(slot: Self.slot(for: pick.basis), productID: pick.hit.id))
            }
            for row in partners {
                await tracker.track(.recImpression(slot: .crosswalk, productID: row.hit.id))
            }
        }
    }

    /// The view reports a tap before handing the hit to whoever opens it.
    public func tapped(_ pick: DiscoverHit) {
        guard let tracker else { return }
        Task { await tracker.track(.recTapped(slot: Self.slot(for: pick.basis), productID: pick.hit.id)) }
    }

    /// Whether the dismiss gesture is offered at all — no store, no write,
    /// no gesture (the chips rule: an editor that writes nowhere must not
    /// be offered).
    public var supportsDismissal: Bool {
        store?.dismiss != nil
    }

    /// "Not for me." Optimistic: the row leaves now and comes back only if
    /// the write fails — the fit section's contract. The event fires only
    /// after the write lands: rec_dismissed measures dismissals that exist,
    /// not taps that bounced.
    public func dismiss(_ pick: DiscoverHit, reason: String?) {
        guard let dismiss = store?.dismiss,
              let index = picks.firstIndex(of: pick) else { return }
        picks.remove(at: index)
        dismissTask = Task { [tracker] in
            do {
                try await dismiss(pick.hit.id, reason)
                await tracker?.track(.recDismissed(
                    slot: Self.slot(for: pick.basis), productID: pick.hit.id, reason: reason
                ))
            } catch {
                guard !Task.isCancelled else { return }
                picks.insert(pick, at: min(index, picks.count))
            }
        }
    }

    var dismissTask: Task<Void, Never>?

    public func tappedCrosswalk(_ row: CrosswalkHit) {
        guard let tracker else { return }
        Task { await tracker.track(.recTapped(slot: .crosswalk, productID: row.hit.id)) }
    }

    /// Storage key → fetchable URL, the shelf's composition rule: nil base or
    /// nil key degrades to the drawn mock, never a broken image (GLO-83).
    public func imageURL(for hit: CatalogHit) -> URL? {
        guard let imageBase, let key = hit.catalogImageKey else { return nil }
        return imageBase.appending(path: key)
    }
}
