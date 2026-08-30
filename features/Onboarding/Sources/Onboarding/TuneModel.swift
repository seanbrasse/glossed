import DataKit
import Foundation
import Observation

/// The tune screen's state (`G.Tune`, GLO-18/GLO-20): the three questions
/// that deliberately never gated the payoff — skin type, concerns, brands.
/// The eyebrow is the doctrine: AFTER SIGNUP · NEVER BEFORE THE PAYOFF.
///
/// Loads the current answers (tuning is an edit, not a re-ask) and saves
/// through a seam the app fills; the feature never decides how the write
/// happens. Concerns and brands toggle freely including to empty — unlike
/// domains, an empty concern list is a fine answer.
@MainActor
@Observable
public final class TuneModel {
    /// What the screen edits, whole — the seam receives all of it and the
    /// app decides what its write can carry.
    public struct Selection: Equatable, Sendable {
        public var skinType: SkinType?
        public var concerns: [String]
        public var brands: [String]

        public init(skinType: SkinType? = nil, concerns: [String] = [], brands: [String] = []) {
            self.skinType = skinType
            self.concerns = concerns
            self.brands = brands
        }
    }

    public enum Phase: Equatable {
        case loading, ready, saving, saved
    }

    public private(set) var phase = Phase.loading
    public var selection = Selection()
    /// A failed save, in words — the selection stays editable.
    public private(set) var saveError: GlossedError?

    /// The kit's concern vocabulary, verbatim.
    public nonisolated static let concernOptions = [
        "acne", "texture", "redness", "dark spots", "fine lines", "dryness"
    ]

    private let load: (@Sendable () async throws -> Selection)?
    private let save: (@Sendable (Selection) async throws -> Void)?
    var task: Task<Void, Never>?

    public init(
        load: (@Sendable () async throws -> Selection)? = nil,
        save: (@Sendable (Selection) async throws -> Void)? = nil
    ) {
        self.load = load
        self.save = save
    }

    public func loadCurrent() {
        task?.cancel()
        guard let load else {
            phase = .ready
            return
        }
        phase = .loading
        task = Task {
            // A failed load starts blank rather than blocking the screen —
            // tuning from scratch beats not tuning.
            let current = await (try? load()) ?? Selection()
            guard !Task.isCancelled else { return }
            selection = current
            phase = .ready
        }
    }

    public func toggleConcern(_ concern: String) {
        toggle(concern, in: &selection.concerns)
    }

    public func toggleBrand(_ brand: String) {
        toggle(brand, in: &selection.brands)
    }

    private func toggle(_ value: String, in list: inout [String]) {
        if let index = list.firstIndex(of: value) {
            list.remove(at: index)
        } else {
            list.append(value)
        }
    }

    public func saveSelection(onSaved: @escaping () -> Void) {
        guard let save else {
            onSaved()
            return
        }
        phase = .saving
        saveError = nil
        task = Task {
            do {
                try await save(selection)
                guard !Task.isCancelled else { return }
                phase = .saved
                onSaved()
            } catch {
                guard !Task.isCancelled else { return }
                phase = .ready
                saveError = GlossedError.from(error)
            }
        }
    }
}
