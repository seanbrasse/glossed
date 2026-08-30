import DataKit
import Foundation
import Supabase
import Testing
@testable import Browse

/// Decoded from the wire shape rather than constructed, so these exercise the
/// same path the RPC takes.
private func row(n: Int, minN: Int = 5, window: Int = 30) -> TrendingVariant {
    let json = Data("""
    {"variant_id":"\(UUID().uuidString)","brand_name":"fenty beauty",
     "product_name":"pro filt'r","shade_code":"220","n_logs":\(n),"min_n":\(minN),
     "meets_min_n":\(n >= minN),"window_days":\(window),
     "refreshed_at":"2026-08-29T19:07:29Z"}
    """.utf8)
    // swiftlint:disable:next force_try
    return try! PostgrestClient.Configuration.jsonDecoder.decode(TrendingVariant.self, from: json)
}

private func store(_ rows: [TrendingVariant]) -> TrendingStore {
    TrendingStore(load: { _, _ in rows })
}

@MainActor
@Test func belowThresholdRowsRenderRatherThanVanish() async {
    // §4: min-n is rendered, not hidden. Dropping these would make a young
    // surface look empty rather than honest.
    let model = TrendingModel(store: store([row(n: 1), row(n: 2)]))
    await model.load()
    #expect(model.rows.count == 2)
    #expect(model.allBelowThreshold)
    #expect(model.rows[0].notEnoughYetLine == "not enough yet · 1 of 5")
}

@MainActor
@Test func aQualifyingRowDropsTheNotEnoughLine() async {
    let model = TrendingModel(store: store([row(n: 12)]))
    await model.load()
    #expect(!model.allBelowThreshold)
    #expect(model.rows[0].notEnoughYetLine == nil)
}

@MainActor
@Test func theCohortLineNamesWhoseNThisIs() {
    // domain.md §5's companion rule: a cohort claim says whose n it is.
    let everyone = TrendingModel(store: store([row(n: 1)]))
    #expect(everyone.cohortLine == "among everyone")

    let combo = TrendingModel(store: store([row(n: 1)]), skinType: "combo")
    #expect(combo.cohortLine == "among people with combo skin")
}

@MainActor
@Test func theCohortLabelFollowsTheFilter() async {
    // Derived from the same value that builds the query, so the label cannot
    // drift from what was actually asked.
    let model = TrendingModel(store: store([row(n: 1)]))
    await model.setCohort("oily")
    #expect(model.skinType == "oily")
    #expect(model.cohortLine.contains("oily"))
}

@MainActor
@Test func theWindowTravelsWithTheRows() async {
    // "37 people" says nothing without the period it is over.
    let model = TrendingModel(store: store([row(n: 1, window: 30)]))
    await model.load()
    #expect(model.windowLine == "in the last 30 days")
}

@MainActor
@Test func anEmptyWindowSaysSoWithoutAWindowClaim() async {
    // No rows means no window to state, and inventing one would be a claim
    // about data that does not exist.
    let model = TrendingModel(store: store([]))
    await model.load()
    #expect(model.isEmpty)
    #expect(model.windowLine.isEmpty)
    #expect(!model.allBelowThreshold)
}

@MainActor
@Test func aFailedLoadIsNotAnEmptyWindow() async {
    struct Boom: Error {}
    let model = TrendingModel(store: TrendingStore(load: { _, _ in throw Boom() }))
    await model.load()
    #expect(model.errorMessage != nil)
}
