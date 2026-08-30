import DataKit
import Foundation
import Supabase
import Testing
@testable import Browse

private func browseRow(handle: String = "juli_r", steps: Int = 4, shelf: Int = 12) -> BrowseRoutine {
    let json = Data("""
    {"routine_id":"\(UUID().uuidString)","title":"morning","slot":"am",
     "owner_handle":"\(handle)","step_n":\(steps),"owner_shelf_n":\(shelf),
     "started_on":"2026-08-01","created_at":"2026-08-29T12:00:00Z"}
    """.utf8)
    // swiftlint:disable:next force_try
    return try! PostgrestClient.Configuration.jsonDecoder.decode(BrowseRoutine.self, from: json)
}

private func store(
    browse: @escaping @Sendable (RoutineSlot, String?, String?) async throws -> [BrowseRoutine] = { _, _, _ in [] },
    detail: @escaping @Sendable (UUID) async throws -> RoutineDetail? = { _ in nil }
) -> RoutinesStore {
    RoutinesStore(browse: browse, detail: detail)
}

@MainActor
@Test func hairPatternOnlyNarrowsWashDay() async {
    // A hair filter on an AM routine filters by something the slot has no
    // opinion about, and would silently hide routines that match.
    let model = RoutinesBrowseModel(store: store())
    await model.setSlot(.washDay)
    await model.setFilters(skinType: nil, hairPattern: "3b")
    #expect(model.hairPattern == "3b")

    await model.setSlot(.am)
    #expect(model.hairPattern == nil)
}

@MainActor
@Test func aHairFilterIsRefusedOutsideWashDay() async {
    let model = RoutinesBrowseModel(store: store())
    await model.setSlot(.pm)
    await model.setFilters(skinType: "combo", hairPattern: "4c")
    #expect(model.skinType == "combo")
    #expect(model.hairPattern == nil)
}

@MainActor
@Test func theFilterLineNamesWhoseRoutinesTheseAre() async {
    let model = RoutinesBrowseModel(store: store())
    #expect(model.filterLine == "from everyone")
    await model.setFilters(skinType: "combo", hairPattern: nil)
    #expect(model.filterLine == "from people with combo skin")
}

@MainActor
@Test func fourExclusionsGetOneMessage() async {
    // Scope, discoverable, unapproved title and block all produce nothing.
    // Naming which applied would leak the one that did.
    let model = RoutinesBrowseModel(store: store())
    await model.load()
    #expect(model.isEmpty)
    #expect(!model.emptyLine.contains("private"))
    #expect(!model.emptyLine.contains("blocked"))
}

@MainActor
@Test func browseRowsCarryBothCounts() async {
    let model = RoutinesBrowseModel(store: store(browse: { _, _, _ in [browseRow(steps: 4, shelf: 12)] }))
    await model.load()
    #expect(model.rows.first?.stepN == 4)
    #expect(model.rows.first?.ownerShelfN == 12)
}

@MainActor
@Test func anInvisibleRoutineIsIndistinguishableFromAMissingOne() async {
    // routineDetail returns nil for both, and the screen must not tell them
    // apart.
    let model = RoutineDetailModel(store: store(detail: { _ in nil }), routineID: UUID())
    await model.load()
    #expect(model.isUnavailable)
    #expect(model.stepCount == 0)
}

@MainActor
@Test func theStepCountIsWhatTheViewerCanActuallySee() async {
    // A step whose product the viewer cannot read is dropped by the
    // repository, so the rendered n must count what is shown rather than what
    // the routine holds — otherwise the claim overstates the evidence.
    let detail = RoutineDetail(
        routineID: UUID(), title: "morning", slot: .am, startedOn: nil,
        steps: [
            RoutineStep(
                position: 1,
                userItemID: UUID(),
                brandName: "rhode",
                productName: "pineapple refresh",
                variantLabel: nil
            )
        ]
    )
    let model = RoutineDetailModel(store: store(detail: { _ in detail }), routineID: UUID())
    await model.load()
    #expect(model.stepCount == 1)
}
