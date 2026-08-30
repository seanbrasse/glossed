import Foundation

// The looks' owner-side wire formats and the pure rules built on them. Split
// from `LooksRepository.swift` for the 300-line ceiling; the same split
// `CollectionsWireRows.swift` and `ShelfWireRows.swift` are.

extension LooksRepository {
    struct OwnLookRow: Decodable, Sendable {
        let id: UUID
        let caption: String?
        let state: LookState
        let postedAt: Date?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, caption, state
            case postedAt = "posted_at"
            case createdAt = "created_at"
        }
    }

    struct OwnPhotoRow: Decodable, Sendable {
        let id: UUID
        let lookID: UUID
        let r2Key: String
        let position: Int

        enum CodingKeys: String, CodingKey {
            case id, position
            case lookID = "look_id"
            case r2Key = "r2_key"
        }
    }

    struct OwnTagRow: Decodable, Sendable {
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

    /// The whole payload of `publish`, and deliberately one column.
    ///
    /// A dictionary would have done, but a type is what makes the payload
    /// testable: the test below asserts these keys are exactly `["state"]`, so
    /// adding `posted_at` or `updated_at` here — neither of which
    /// `authenticated` may write (0048) — fails in Swift rather than as a
    /// `42501` from Postgres.
    struct StateUpdate: Encodable, Sendable {
        let state: LookState
    }

    /// Pure assembly, so the ordering rule is testable without a database.
    ///
    /// **Photos are sorted here even though the query already ordered them.**
    /// PostgREST's `order` is a request, not a guarantee the decoder preserves
    /// across a grouped rebuild, and `look_photos` has its own `id` primary
    /// key — nothing about the storage order is positional. A look whose photos
    /// draw in the wrong order is silently wrong rather than visibly broken,
    /// which is the failure worth spending a sort on.
    ///
    /// Ties are broken by `id` so the order is deterministic when two photos
    /// somehow share a position.
    static func assemble(
        looks: [OwnLookRow], photos: [OwnPhotoRow], tags: [OwnTagRow]
    ) -> [MyLook] {
        let photosByLook = Dictionary(grouping: photos, by: \.lookID)
        let tagsByLook = Dictionary(grouping: tags, by: \.lookID)
        return looks.map { look in
            let ordered = (photosByLook[look.id] ?? [])
                .sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) }
                .map { LookPhoto(photoID: $0.id, r2Key: $0.r2Key, position: $0.position) }
            let pinned = (tagsByLook[look.id] ?? [])
                .map { LookTag(variantID: $0.variantID, x: $0.x, y: $0.y) }
            return MyLook(
                lookID: look.id,
                caption: look.caption,
                state: look.state,
                postedAt: look.postedAt,
                createdAt: look.createdAt,
                photos: ordered,
                tags: pinned
            )
        }
    }
}
