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

        public var id: String {
            switch self {
            case let .pick(hit): "pick-\(hit.id)"
            case .crosswalk: "crosswalk"
            case .trendingTeaser: "trending"
            }
        }
    }

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
        return cards
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
            let (loadedPicks, loadedPartners) = await (feed, partners)
            guard !Task.isCancelled else { return }
            picks = loadedPicks ?? []
            crosswalk = loadedPartners ?? []
            phase = picks.isEmpty && crosswalk.isEmpty ? .empty : .loaded
            recordImpressions()
        }
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
