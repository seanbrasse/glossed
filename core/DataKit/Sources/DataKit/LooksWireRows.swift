import Foundation

// The looks' owner-side wire formats and the pure rules built on them. Split
// from `LooksRepository.swift` for the 300-line ceiling; the same split
// `CollectionsWireRows.swift` and `ShelfWireRows.swift` are.

extension LooksRepository {
    // MARK: - What the client SENDS (saveDraft)

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
        /// Sent since 0049: `look_tags.look_photo_id` references it, so the
        /// client mints it (LookDraft.Photo) rather than reading it back.
        let id: UUID
        let lookID: UUID
        let r2Key: String
        let position: Int

        enum CodingKeys: String, CodingKey {
            case id
            case lookID = "look_id"
            case r2Key = "r2_key"
            case position
        }
    }

    /// A spot (0049's `look_tags`): a place on ONE photo. The products it
    /// holds ride separately in `TagVariantRow`.
    struct TagSpotRow: Encodable {
        let id: UUID
        let lookPhotoID: UUID
        let x: Double
        let y: Double

        enum CodingKeys: String, CodingKey {
            case id, x, y
            case lookPhotoID = "look_photo_id"
        }
    }

    struct TagVariantRow: Encodable {
        let lookTagID: UUID
        let variantID: UUID
        let position: Int

        enum CodingKeys: String, CodingKey {
            case lookTagID = "look_tag_id"
            case variantID = "variant_id"
            case position
        }
    }

    // MARK: - What the client READS (mine)

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

    /// A spot row (0049): the tag's identity and where it sits on WHICH photo.
    /// The look is reachable through the photo, so the row does not carry it.
    struct OwnTagRow: Decodable, Sendable {
        let id: UUID
        let lookPhotoID: UUID
        let x: Double
        let y: Double

        enum CodingKeys: String, CodingKey {
            case id, x, y
            case lookPhotoID = "look_photo_id"
        }
    }

    /// One product inside a spot (0049's `look_tag_variants`).
    struct OwnTagVariantRow: Decodable, Sendable {
        let lookTagID: UUID
        let variantID: UUID
        let position: Int

        enum CodingKeys: String, CodingKey {
            case lookTagID = "look_tag_id"
            case variantID = "variant_id"
            case position
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
        looks: [OwnLookRow], photos: [OwnPhotoRow], tags: [OwnTagRow], variants: [OwnTagVariantRow]
    ) -> [MyLook] {
        let photosByLook = Dictionary(grouping: photos, by: \.lookID)
        let tagsByPhoto = Dictionary(grouping: tags, by: \.lookPhotoID)
        let variantsByTag = Dictionary(grouping: variants, by: \.lookTagID)
        return looks.map { look in
            let ordered = (photosByLook[look.id] ?? [])
                .sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) }
                .map { LookPhoto(photoID: $0.id, r2Key: $0.r2Key, position: $0.position) }
            // A look's spots, reached through its photos — the only route the
            // schema offers since 0049, so a spot on a stranger's photo cannot
            // be grouped in by construction. Products inside a spot sort by
            // (position, variant_id): position is deliberately non-unique and
            // the tie-break is 0049's own documented rule.
            let spots = ordered.flatMap { photo in
                (tagsByPhoto[photo.photoID] ?? [])
                    .sorted { $0.id.uuidString < $1.id.uuidString }
                    .map { tag in
                        LookSpot(
                            tagID: tag.id,
                            photoID: photo.photoID,
                            x: tag.x,
                            y: tag.y,
                            products: (variantsByTag[tag.id] ?? [])
                                .sorted {
                                    ($0.position, $0.variantID.uuidString) < ($1.position, $1.variantID.uuidString)
                                }
                                .map { LookSpotProduct(variantID: $0.variantID, position: $0.position) }
                        )
                    }
            }
            return MyLook(
                lookID: look.id,
                caption: look.caption,
                state: look.state,
                postedAt: look.postedAt,
                createdAt: look.createdAt,
                photos: ordered,
                spots: spots
            )
        }
    }
}
