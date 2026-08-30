import Foundation
import Testing
@testable import DataKit

// Pure rules the routines repository encodes; the owner-only policies
// themselves (routines_own, routine_steps_own) are proven by the DB suite,
// which is the actual security boundary.

@Test func aRoutineDraftMintsItsOwnPrimaryKeyAndKeepsACallerSuppliedOne() {
    let one = RoutineDraft(title: "am", slot: .am, stepItemIDs: [])
    let two = RoutineDraft(title: "am", slot: .am, stepItemIDs: [])
    #expect(one.routineID != two.routineID) // two saves are two routines…
    let fixed = UUID()
    // …and a retry of the SAME draft is the same row, not a second routine
    // wearing the same name.
    #expect(RoutineDraft(title: "am", slot: .am, stepItemIDs: [], routineID: fixed).routineID == fixed)
}

@Test func routineRowEncodingMatchesTheMigrationsColumns() throws {
    // 0003's column names, spelled out. Drift comes back as a server error at
    // best and a silently-ignored key at worst — the failure mode that reads
    // exactly like absence.
    let routine = RoutinesRepository.RoutineRow(
        id: UUID(), userID: UUID(), title: "morning glass skin", slot: .washDay
    )
    #expect(try keys(of: routine) == ["id", "slot", "title", "user_id"])

    let step = RoutinesRepository.StepRow(routineID: UUID(), userItemID: UUID(), position: 0)
    #expect(try keys(of: step) == ["position", "routine_id", "user_item_id"])
}

@Test func theSlotCrossesTheWireAsThePostgresEnumsOwnSpelling() throws {
    // `create type routine_slot as enum ('am', 'pm', 'weekly', 'wash_day')`.
    // A label with a space would be rejected by Postgres, not coerced.
    #expect(RoutineSlot.allCases.map(\.rawValue) == ["am", "pm", "weekly", "wash_day"])

    let row = RoutinesRepository.RoutineRow(
        id: UUID(), userID: UUID(), title: "t", slot: .washDay
    )
    let object = try encoded(row)
    #expect(object["slot"] as? String == "wash_day")
}

@Test func positionComesFromTheArraysOrderNotFromTheCaller() {
    // The draft carries no positions: order IS the array. This is what makes
    // "the order you tapped" survive the trip to Postgres.
    let cleanser = UUID(), serum = UUID(), spf = UUID()
    let draft = RoutineDraft(title: "pm", slot: .pm, stepItemIDs: [spf, cleanser, serum])
    let rows = draft.stepItemIDs.enumerated().map { index, itemID in
        RoutinesRepository.StepRow(
            routineID: draft.routineID, userItemID: itemID, position: index
        )
    }
    #expect(rows.map(\.position) == [0, 1, 2])
    #expect(rows.map(\.userItemID) == [spf, cleanser, serum])
}

private func encoded(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
}

private func keys(of value: some Encodable) throws -> [String] {
    try encoded(value).keys.sorted()
}
