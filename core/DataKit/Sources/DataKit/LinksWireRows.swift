import Foundation

// The link pairs' wire formats. Split from `LinksRepository.swift` for the
// 300-line ceiling — LooksWireRows' split, one repository over.

extension LinksRepository {
    struct LookRoutineRow: Encodable {
        let lookID: UUID
        let routineID: UUID
        let position: Int

        enum CodingKeys: String, CodingKey {
            case lookID = "look_id"
            case routineID = "routine_id"
            case position
        }
    }

    struct LookCollectionRow: Encodable {
        let lookID: UUID
        let collectionID: UUID
        let position: Int

        enum CodingKeys: String, CodingKey {
            case lookID = "look_id"
            case collectionID = "collection_id"
            case position
        }
    }

    struct RoutineCollectionRow: Encodable {
        let routineID: UUID
        let collectionID: UUID
        let position: Int

        enum CodingKeys: String, CodingKey {
            case routineID = "routine_id"
            case collectionID = "collection_id"
            case position
        }
    }

    struct EmbeddedTitle: Decodable {
        let title: String
    }

    struct EmbeddedRoutineRow: Decodable {
        let routineID: UUID
        let position: Int
        /// Optional on purpose: an embed the caller's RLS refuses arrives as
        /// null, and `links` drops the row rather than drawing a blank chip.
        let routines: EmbeddedTitle?

        enum CodingKeys: String, CodingKey {
            case routineID = "routine_id"
            case position, routines
        }
    }

    struct EmbeddedRoutineCollectionRow: Decodable {
        let routineID: UUID
        let collectionID: UUID
        let position: Int
        let collections: EmbeddedTitle?

        enum CodingKeys: String, CodingKey {
            case routineID = "routine_id"
            case collectionID = "collection_id"
            case position, collections
        }
    }

    struct EmbeddedCollectionRow: Decodable {
        let collectionID: UUID
        let position: Int
        let collections: EmbeddedTitle?

        enum CodingKeys: String, CodingKey {
            case collectionID = "collection_id"
            case position, collections
        }
    }
}
