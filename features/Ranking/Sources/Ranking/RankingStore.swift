import DataKit
import Foundation

/// How a ranking session reaches its two reads and its one write — the seam
/// shape every feature uses (`LeaderboardStore`, `ProductFitStore`).
///
/// Closures rather than a repository, because the rules that decide what a
/// session *means* are the whole point of this feature and should be testable
/// without a running stack. `RankingEngine` has always been testable that way;
/// until now nothing stood between it and Postgres, which is why the screen it
/// drives has never been reachable in the app.
public struct RankingStore: Sendable {
    /// Every row the user holds. The session needs one category's rows, and
    /// the shelf read is the only one carrying a row's category, its position,
    /// its start date and its status together.
    public var shelf: @Sendable () async throws -> [ShelfRow]

    /// The category's own rules. `wearInDays` and `rankUnlockMin` are read as
    /// columns, never assumed: a cleanser that ranks the day you open it and a
    /// retinoid that waits twelve weeks are one code path (PRD §03 — "wear-in
    /// is a field on the category").
    public var categories: @Sendable (_ domain: Domain) async throws -> [DataKit.Category]

    /// The whole session, atomically: comparisons appended, positions rebuilt.
    /// Safe to retry — the RPC dedupes on each comparison's client id.
    public var apply: @Sendable (
        _ faceOffs: [FaceOffRecord],
        _ positions: [RankPosition]
    ) async throws -> Void

    public init(
        shelf: @escaping @Sendable () async throws -> [ShelfRow],
        categories: @escaping @Sendable (Domain) async throws -> [DataKit.Category],
        apply: @escaping @Sendable ([FaceOffRecord], [RankPosition]) async throws -> Void
    ) {
        self.shelf = shelf
        self.categories = categories
        self.apply = apply
    }

    /// The live path, through the frozen core: the shelf read, the category
    /// reference read, and `apply_face_off_session`.
    public static func repository(
        shelf: ShelfRepository,
        catalog: CatalogRepository,
        ranking: RankingRepository
    ) -> RankingStore {
        RankingStore(
            shelf: { try await shelf.shelf() },
            categories: { try await catalog.categories(domain: $0) },
            apply: { try await ranking.apply(faceOffs: $0, positions: $1) }
        )
    }
}
