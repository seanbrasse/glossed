import Foundation
import Supabase

/// A draft look as the composer hands it over, in one shape — the repository
/// writes parent and children itself so a caller cannot invent an ordering
/// that leaves a photo-less look row behind on a mid-flight failure.
public struct LookDraft: Sendable {
    public struct Photo: Sendable {
        public let r2Key: String
        public let position: Int

        public init(r2Key: String, position: Int) {
            self.r2Key = r2Key
            self.position = position
        }
    }

    public struct Tag: Sendable {
        public let variantID: UUID
        public let x: Double
        public let y: Double

        public init(variantID: UUID, x: Double, y: Double) {
            self.variantID = variantID
            self.x = x
            self.y = y
        }
    }

    public let caption: String?
    public let photos: [Photo]
    public let tags: [Tag]
    /// Idempotency, the LogDraft pattern with 0043's shape: the caller mints
    /// the look's PRIMARY KEY, so a retry after a failed save upserts the same
    /// row rather than minting a duplicate — no client_id column needed.
    public let lookID: UUID

    public init(caption: String?, photos: [Photo], tags: [Tag], lookID: UUID = UUID()) {
        self.caption = caption
        self.photos = photos
        self.tags = tags
        self.lookID = lookID
    }
}

/// Writes for the feed's photo posts (0043). Session-scoped opening, Aug 30:
/// granted for exactly this repository. Everything lands as a DRAFT — the
/// state machine's public transition belongs to moderation (GLO-26), and no
/// client write can perform it (RLS: `state` is not client-settable past the
/// insert default).
public struct LooksRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    struct LookRow: Encodable {
        let id: UUID
        let userID: UUID
        let caption: String?

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case caption
        }
    }

    struct PhotoRow: Encodable {
        let lookID: UUID
        let r2Key: String
        let position: Int

        enum CodingKeys: String, CodingKey {
            case lookID = "look_id"
            case r2Key = "r2_key"
            case position
        }
    }

    struct TagRow: Encodable {
        let lookID: UUID
        let variantID: UUID
        let x: Double
        let y: Double

        enum CodingKeys: String, CodingKey {
            case lookID = "look_id"
            case variantID = "variant_id"
            case x, y
        }
    }

    private struct InsertedID: Decodable {
        let id: UUID
    }

    /// Parent first, children after. A mid-flight failure cannot duplicate:
    /// the caller still holds the draft, whose lookID is the primary key, so
    /// retrying the SAME draft upserts the same parent and re-lands the
    /// children — resume, not restart.
    public func saveDraft(_ draft: LookDraft) async throws(GlossedError) -> UUID {
        let userID = try await client.requireUserID()
        let lookID: UUID = try await run {
            let inserted: InsertedID = try await client.supabase
                .from("looks")
                .upsert(
                    LookRow(id: draft.lookID, userID: userID, caption: draft.caption),
                    onConflict: "id"
                )
                .select("id")
                .single()
                .execute()
                .value
            return inserted.id
        }
        try await run {
            if !draft.photos.isEmpty {
                let rows = draft.photos.map {
                    PhotoRow(lookID: lookID, r2Key: $0.r2Key, position: $0.position)
                }
                try await client.supabase
                    .from("look_photos")
                    .upsert(rows, onConflict: "look_id,position")
                    .execute()
            }
            if !draft.tags.isEmpty {
                let rows = draft.tags.map {
                    TagRow(lookID: lookID, variantID: $0.variantID, x: $0.x, y: $0.y)
                }
                try await client.supabase
                    .from("look_tags")
                    .upsert(rows, onConflict: "look_id,variant_id")
                    .execute()
            }
        }
        return lookID
    }

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}
