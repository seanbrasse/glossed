import Foundation
import Supabase
import Testing
@testable import DataKit

// Wire shapes and the render rules the types carry. The exclusions themselves —
// scope, discoverable, unapproved titles, blocks — are proven by pgTAP.

@Test func routineSlotsMatchTheDatabaseEnum() {
    // wash day is first-class, not a weekly with a note.
    #expect(Set(RoutineSlot.allCases.map(\.rawValue)) == ["am", "pm", "weekly", "wash_day"])
    #expect(RoutineSlot.washDay.label == "wash day")
}

@Test func slotLabelsAreLowercase() {
    for slot in RoutineSlot.allCases {
        #expect(slot.label == slot.label.lowercased())
    }
}

@Test func aBrowseRowCarriesItsN() throws {
    // step_n and owner_shelf_n are the evidence behind the row. No row renders
    // without them, so neither is optional.
    let json = Data("""
    {"routine_id":"11111111-1111-4111-8111-111111111111","title":"morning",
     "slot":"am","owner_handle":"maya_k","step_n":4,"owner_shelf_n":12,
     "started_on":"2026-08-01","created_at":"2026-08-29T12:00:00Z"}
    """.utf8)
    // The platform decoder, not a hand-rolled one — this is the decoder the
    // repository actually uses, so a shape it cannot handle fails here.
    let row = try PostgrestClient.Configuration.jsonDecoder.decode(BrowseRoutine.self, from: json)
    #expect(row.title == "morning")
    // A bare calendar day parses where the platform decoder alone would throw.
    #expect(row.startedOn != nil)
    #expect(row.slot == .am)
    #expect(row.stepN == 4)
    #expect(row.ownerShelfN == 12)
    #expect(row.id == row.routineID)
}

@Test func minNIsRenderedNotHidden() {
    // The rule the whole trending surface turns on (§4). A below-threshold row
    // still appears and says how far along it is — a young surface should look
    // honest rather than empty.
    let thin = TrendingVariant(
        variantID: UUID(), brandName: "fenty beauty", productName: "pro filt'r",
        shadeCode: "220", nLogs: 2, minN: 5, meetsMinN: false,
        windowDays: 30, refreshedAt: Date()
    )
    #expect(thin.notEnoughYetLine == "not enough yet · 2 of 5")
}

@Test func aQualifyingRowHasNoNotEnoughLine() {
    // Returning nil above the threshold is what stops a caller printing the
    // evidence line twice, or printing it where it does not apply.
    let strong = TrendingVariant(
        variantID: UUID(), brandName: "rhode", productName: "pineapple refresh",
        shadeCode: nil, nLogs: 37, minN: 5, meetsMinN: true,
        windowDays: 30, refreshedAt: Date()
    )
    #expect(strong.notEnoughYetLine == nil)
}

@Test func theThresholdAndWindowTravelWithTheRow() throws {
    // The client never hard-codes either. min_n is tunable server-side, and a
    // velocity claim without its window is meaningless — "37 people" means
    // nothing until you know it is 37 in 30 days.
    let json = Data("""
    {"variant_id":"22222222-2222-4222-8222-222222222222","brand_name":"ouai",
     "product_name":"hair oil","shade_code":null,"n_logs":9,"min_n":5,
     "meets_min_n":true,"window_days":30,"refreshed_at":"2026-08-29T19:07:29Z"}
    """.utf8)
    let row = try PostgrestClient.Configuration.jsonDecoder.decode(TrendingVariant.self, from: json)
    #expect(row.minN == 5)
    #expect(row.windowDays == 30)
    #expect(row.shadeCode == nil)
    #expect(row.meetsMinN)
}

@Test func anEmptyBrowseDecodesRatherThanFailing() throws {
    // Empty is expected, not exceptional: four exclusions apply and a viewer
    // may legitimately match nothing. A decoder that threw here would turn the
    // ordinary case into a crash.
    let decoder = PostgrestClient.Configuration.jsonDecoder
    #expect(try decoder.decode([BrowseRoutine].self, from: Data("[]".utf8)).isEmpty)
    #expect(try decoder.decode([TrendingVariant].self, from: Data("[]".utf8)).isEmpty)
}
