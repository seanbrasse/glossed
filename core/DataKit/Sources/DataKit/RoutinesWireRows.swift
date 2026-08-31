import Foundation

// The routines' owner-side wire formats. Split from `RoutinesRepository.swift`
// for the 300-line ceiling — the same split LooksWireRows and
// CollectionsWireRows are.

extension RoutinesRepository {
    struct OwnRoutineRow: Decodable {
        let id: UUID
        let title: String
        let slot: RoutineSlot
        let visibility: PrivacyScope
        let startedOnRaw: String?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, title, slot, visibility
            case startedOnRaw = "started_on"
            case createdAt = "created_at"
        }
    }

    struct OwnStepRow: Decodable {
        let routineID: UUID
        let position: Int
        let userItemID: UUID
        let note: String?

        enum CodingKeys: String, CodingKey {
            case routineID = "routine_id"
            case position, note
            case userItemID = "user_item_id"
        }
    }
}
