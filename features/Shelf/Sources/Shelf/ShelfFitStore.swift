import DataKit
import DesignSystem
import Foundation

// DesignSystem declares `FitAnswer` on its own so the control stays standalone;
// the wire speaks `Fit`. This is the one place the shelf translates between
// them, and it is two exhaustive switches: adding a seventh answer to either
// side is a compile error here, not a fit that silently never persists.

public extension Fit {
    init(answer: FitAnswer) {
        self =
            switch answer {
            case .justRight: .justRight
            case .tooLight: .tooLight
            case .tooDark: .tooDark
            case .tooPink: .tooPink
            case .tooYellow: .tooYellow
            case .tooOrange: .tooOrange
            }
    }

    var answer: FitAnswer {
        switch self {
        case .justRight: .justRight
        case .tooLight: .tooLight
        case .tooDark: .tooDark
        case .tooPink: .tooPink
        case .tooYellow: .tooYellow
        case .tooOrange: .tooOrange
        }
    }
}

/// How the sheet's fit section reaches persistence: read the saved answer when
/// an item opens, write the whole set when it changes.
///
/// Two closures rather than a protocol because that is all there is — the
/// model can be tested against a recording stub, the picker's fixture states
/// run with no store at all, and the live wiring is one line per side.
public struct ShelfFitStore: Sendable {
    public var load: @Sendable (UUID) async throws -> Set<FitAnswer>
    public var save: @Sendable (UUID, Set<FitAnswer>) async throws -> Void

    public init(
        load: @escaping @Sendable (UUID) async throws -> Set<FitAnswer>,
        save: @escaping @Sendable (UUID, Set<FitAnswer>) async throws -> Void
    ) {
        self.load = load
        self.save = save
    }

    /// The live path: `item_fits` through the frozen core — `fits(itemID:)`
    /// reading, `capture_fit` replacing wholesale — translated at this edge.
    public static func repository(_ repository: ShelfRepository) -> ShelfFitStore {
        ShelfFitStore(
            load: { itemID in
                try await Set(repository.fits(itemID: itemID).map(\.answer))
            },
            save: { itemID, answers in
                try await repository.captureFit(itemID: itemID, fits: Set(answers.map(Fit.init(answer:))))
            }
        )
    }
}
