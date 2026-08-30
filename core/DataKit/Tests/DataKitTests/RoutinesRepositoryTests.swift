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

// The owner-side reads (GLO-230). `mine()` itself needs a session and a
// database, so what is tested here is the part that can be wrong SILENTLY:
// assembly. The policies (routines_own) are proven by the DB suite, which is
// the actual security boundary.

@Test func stepsComeBackInPositionOrderNoMatterWhatOrderTheyArriveIn() {
    // Written to fail first, and it did: without the sort in `assemble` the
    // steps came back in arrival order — cleanser LAST. A routine rendered out
    // of order is silently wrong rather than visibly broken, and nothing about
    // `routine_steps` storage is positional: its primary key is
    // (routine_id, user_item_id), so the rows have no natural order at all.
    let routineID = UUID()
    let cleanser = UUID(), serum = UUID(), spf = UUID()
    let routine = RoutinesRepository.OwnRoutineRow(
        id: routineID, title: "am", slot: .am, startedOnRaw: nil, createdAt: Date()
    )
    // Deliberately shuffled — this is what a grouped rebuild can hand back.
    let steps = [
        RoutinesRepository.OwnStepRow(routineID: routineID, position: 2, userItemID: spf),
        RoutinesRepository.OwnStepRow(routineID: routineID, position: 0, userItemID: cleanser),
        RoutinesRepository.OwnStepRow(routineID: routineID, position: 1, userItemID: serum)
    ]
    let names = [cleanser, serum, spf].map {
        ShelfNameRow(userItemID: $0, brandName: "b", productName: "p", variantLabel: nil)
    }

    let assembled = RoutinesRepository.assemble(routines: [routine], steps: steps, names: names)
    #expect(assembled.count == 1)
    #expect(assembled[0].steps.map(\.position) == [0, 1, 2])
    #expect(assembled[0].steps.map(\.userItemID) == [cleanser, serum, spf])
}

@Test func aStepWhoseProductCannotBeReadIsDroppedRatherThanRenderedBlank() {
    // Same choice `routineDetail` makes: a numbered gap invites the question
    // of what is hidden. The count follows the array, so the card cannot say
    // "3 steps" while drawing two.
    let routineID = UUID()
    let visible = UUID(), unreadable = UUID()
    let routine = RoutinesRepository.OwnRoutineRow(
        id: routineID, title: "pm", slot: .pm, startedOnRaw: nil, createdAt: Date()
    )
    let steps = [
        RoutinesRepository.OwnStepRow(routineID: routineID, position: 0, userItemID: visible),
        RoutinesRepository.OwnStepRow(routineID: routineID, position: 1, userItemID: unreadable)
    ]
    let names = [ShelfNameRow(userItemID: visible, brandName: "b", productName: "p", variantLabel: nil)]

    let assembled = RoutinesRepository.assemble(routines: [routine], steps: steps, names: names)
    #expect(assembled[0].steps.map(\.userItemID) == [visible])
    #expect(assembled[0].stepN == 1) // the n matches what is drawn
}

@Test func aRoutineWithNoStepsAssemblesRatherThanDisappearing() {
    // A stepless routine is a real state — `saveDraft` accepts an empty
    // `stepItemIDs` — and the profile tab has to be able to draw it.
    let routine = RoutinesRepository.OwnRoutineRow(
        id: UUID(), title: "weekly", slot: .weekly, startedOnRaw: nil, createdAt: Date()
    )
    let assembled = RoutinesRepository.assemble(routines: [routine], steps: [], names: [])
    #expect(assembled.count == 1)
    #expect(assembled[0].stepN == 0)
}

@Test func stepsAreGroupedByTheirOwnRoutineAndDoNotLeakAcross() {
    // One read fetches steps for every routine at once; the grouping is the
    // only thing keeping the morning routine's steps out of the evening one.
    let morning = UUID(), evening = UUID()
    let itemA = UUID(), itemB = UUID()
    let routines = [
        RoutinesRepository.OwnRoutineRow(
            id: morning, title: "am", slot: .am, startedOnRaw: nil, createdAt: Date()
        ),
        RoutinesRepository.OwnRoutineRow(
            id: evening, title: "pm", slot: .pm, startedOnRaw: nil, createdAt: Date()
        )
    ]
    let steps = [
        RoutinesRepository.OwnStepRow(routineID: evening, position: 0, userItemID: itemB),
        RoutinesRepository.OwnStepRow(routineID: morning, position: 0, userItemID: itemA)
    ]
    let names = [itemA, itemB].map {
        ShelfNameRow(userItemID: $0, brandName: "b", productName: "p", variantLabel: nil)
    }

    let assembled = RoutinesRepository.assemble(routines: routines, steps: steps, names: names)
    #expect(assembled[0].steps.map(\.userItemID) == [itemA])
    #expect(assembled[1].steps.map(\.userItemID) == [itemB])
}

@Test func theStartedOnDateIsParsedAsACalendarDayNotAnInstant() throws {
    // Every `date` column in the schema needs this — the platform decoder
    // wants a time component and throws on a bare calendar day.
    let routine = RoutinesRepository.OwnRoutineRow(
        id: UUID(), title: "am", slot: .am, startedOnRaw: "2026-03-14", createdAt: Date()
    )
    let assembled = RoutinesRepository.assemble(routines: [routine], steps: [], names: [])
    let day = try #require(assembled[0].startedOn)
    let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: day)
    #expect(parts.year == 2026 && parts.month == 3 && parts.day == 14)
}

@Test func theRenameUpdateCarriesUpdatedAtBecauseRoutinesHasNoTouchTrigger() throws {
    // Probed, not assumed: `pg_trigger` is empty for `routines`, so nothing
    // moves `updated_at` on its own. A rename that shipped only `title` would
    // leave the row claiming it was last changed at creation.
    let update = RoutinesRepository.TitleUpdate(title: "glass skin", updatedAt: "2026-08-30T00:00:00Z")
    #expect(try keys(of: update) == ["title", "updated_at"])
}
