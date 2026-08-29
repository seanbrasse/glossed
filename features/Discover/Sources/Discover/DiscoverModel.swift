import DataKit
import DesignSystem
import Foundation
import Observation

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

    private let store: DiscoverStore?
    private let imageBase: URL?
    var loadTask: Task<Void, Never>?

    public init(store: DiscoverStore?, imageBase: URL? = nil) {
        self.store = store
        self.imageBase = imageBase
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

    /// Storage key → fetchable URL, the shelf's composition rule: nil base or
    /// nil key degrades to the drawn mock, never a broken image (GLO-83).
    public func imageURL(for hit: CatalogHit) -> URL? {
        guard let imageBase, let key = hit.catalogImageKey else { return nil }
        return imageBase.appending(path: key)
    }
}
