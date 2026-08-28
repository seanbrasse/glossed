import Foundation
import Supabase

/// Persists ranking sessions. The *ordering* logic lives in the Ranking feature —
/// this type only carries the result across the boundary, so business rules stay
/// out of the data layer.
public struct RankingRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    /// Applies a whole session atomically: comparisons appended, positions
    /// rebuilt. Safe to retry — the RPC dedupes on each comparison's client id.
    public func apply(
        faceOffs: [FaceOffRecord],
        positions: [RankPosition]
    ) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .rpc("apply_face_off_session", params: FaceOffSessionParams(
                    faceOffs: faceOffs,
                    positions: positions
                ))
                .execute()
        }
    }

    public func positions(
        categoryID: UUID,
        scopeKey: String = "default"
    ) async throws(GlossedError) -> [RankPosition] {
        _ = try await client.requireUserID()
        return try await run {
            try await client.supabase
                .from("rank_positions")
                .select("category_id,scope_key,user_item_id,position")
                .eq("category_id", value: categoryID.uuidString)
                .eq("scope_key", value: scopeKey)
                .order("position")
                .execute()
                .value
        }
    }

    /// Comparisons that count. Skips are excluded by the view, so callers can't
    /// accidentally read "too close to call" as a preference.
    public func scoredComparisonCount(categoryID: UUID) async throws(GlossedError) -> Int {
        _ = try await client.requireUserID()
        let rows: [ScoredFaceOffRow] = try await run {
            try await client.supabase
                .from("scored_face_offs")
                .select("id")
                .eq("category_id", value: categoryID.uuidString)
                .execute()
                .value
        }
        return rows.count
    }

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}

/// One "which do you reach for?" answer. A skip still records the pair — it is
/// data — but carries no preference, which `scored_face_offs` enforces.
public struct FaceOffRecord: Codable, Sendable, Equatable {
    public let categoryID: UUID
    public let scopeKey: String
    public let winnerItemID: UUID
    public let loserItemID: UUID
    public let skipped: Bool
    public let clientID: UUID

    public init(
        categoryID: UUID,
        winnerItemID: UUID,
        loserItemID: UUID,
        skipped: Bool = false,
        scopeKey: String = "default",
        clientID: UUID = UUID()
    ) {
        self.categoryID = categoryID
        self.scopeKey = scopeKey
        self.winnerItemID = winnerItemID
        self.loserItemID = loserItemID
        self.skipped = skipped
        self.clientID = clientID
    }

    enum CodingKeys: String, CodingKey {
        case skipped
        case categoryID = "category_id"
        case scopeKey = "scope_key"
        case winnerItemID = "winner_item_id"
        case loserItemID = "loser_item_id"
        case clientID = "client_id"
    }
}

public struct RankPosition: Codable, Sendable, Equatable {
    public let categoryID: UUID
    public let scopeKey: String
    public let userItemID: UUID
    /// 1-based: #1 is what they reach for first.
    public let position: Int

    public init(categoryID: UUID, userItemID: UUID, position: Int, scopeKey: String = "default") {
        self.categoryID = categoryID
        self.scopeKey = scopeKey
        self.userItemID = userItemID
        self.position = position
    }

    enum CodingKeys: String, CodingKey {
        case position
        case categoryID = "category_id"
        case scopeKey = "scope_key"
        case userItemID = "user_item_id"
    }
}

struct FaceOffSessionParams: Encodable, Sendable {
    let faceOffs: [FaceOffRecord]
    let positions: [RankPosition]

    enum CodingKeys: String, CodingKey {
        case faceOffs = "p_face_offs"
        case positions = "p_positions"
    }
}

struct ScoredFaceOffRow: Decodable, Sendable {
    let id: UUID
}
