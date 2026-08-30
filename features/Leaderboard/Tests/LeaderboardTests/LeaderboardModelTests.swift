import DataKit
import Foundation
import Testing
@testable import Leaderboard

// The model against a recording stub — the ShelfChips test shape. Fixtures
// sit on BOTH sides of every precondition (the session-12 rule): a slug that
// resolves and one that does not, a row above the gate and one below it, a
// threshold of 5 and one that is not 5.

private func lbRow(
    _ name: String,
    pct: Double?,
    n: Int,
    needed: Int = 5,
    reasons: [String]? = nil,
    faceOffs: Int? = nil
) throws -> LeaderboardRow {
    let quoted: [String] = (reasons ?? []).map { "\"\($0)\"" }
    let reasonsJSON: String = reasons == nil ? "null" : "[" + quoted.joined(separator: ",") + "]"
    let pctJSON: String = pct.map { String($0) } ?? "null"
    let faceOffsJSON: String = faceOffs.map { String($0) } ?? "null"
    let id: String = UUID().uuidString
    let categoryID: String = UUID().uuidString
    let raw = Data("""
    {"id":"\(id)","name":"\(name)","brand_name":"b",
     "category_id":"\(categoryID)","category_slug":"blush","domain":"makeup",
     "scope":"canonical","n_face_offs":\(faceOffsJSON),"variant_label":null,
     "catalog_image_key":null,"catalog_image_width":null,"catalog_image_height":null,
     "mean_percentile":\(pctJSON),"n_users":\(n),
     "needed":\(needed),"dislike_reasons":\(reasonsJSON)}
    """.utf8)
    return try JSONDecoder().decode(LeaderboardRow.self, from: raw)
}

private func category(_ slug: String, domain: String = "makeup") throws -> DataKit.Category {
    let raw = Data("""
    {"id":"\(UUID().uuidString)","domain":"\(domain)","slug":"\(slug)","label":"\(slug)",
     "wear_in_days":0,"is_anchor":true,"rank_unlock_min":3}
    """.utf8)
    return try JSONDecoder().decode(DataKit.Category.self, from: raw)
}

private struct RecordedCall {
    let id: UUID
    let wire: String
    let ascending: Bool
}

private actor Recorder {
    private(set) var calls: [RecordedCall] = []
    func add(id: UUID, wire: String, ascending: Bool) {
        calls.append(RecordedCall(id: id, wire: wire, ascending: ascending))
    }
}

private func recordingStore(
    categories: [DataKit.Category],
    rows: [LeaderboardRow],
    recorder: Recorder
) -> LeaderboardStore {
    LeaderboardStore(
        rows: { id, wire, ascending in
            await recorder.add(id: id, wire: wire, ascending: ascending)
            return rows
        },
        categories: { _ in categories }
    )
}

// ── opening: the slug resolves against the pills, or it doesn't ────────────

@MainActor
@Test func loadResolvesTheOpeningSlugAndLoadsItsBoard() async throws {
    let blush = try category("blush")
    let recorder = Recorder()
    let store = try recordingStore(
        categories: [blush, category("foundation")],
        rows: [lbRow("a", pct: 0.9, n: 12)],
        recorder: recorder
    )
    let model = LeaderboardModel(store: store, categorySlug: "blush", domain: .makeup)
    model.load()
    await model.loadTask?.value
    #expect(model.selectedCategoryID == blush.id)
    #expect(model.rows.count == 1)
    #expect(model.isLoading == false)
    let call = try #require(await recorder.calls.first)
    #expect(call.id == blush.id)
}

@MainActor
@Test func anUnresolvableSlugRendersAnEmptyBoardNeverAWrongOne() async throws {
    let recorder = Recorder()
    let store = try recordingStore(
        categories: [category("blush")],
        rows: [lbRow("a", pct: 0.9, n: 12)],
        recorder: recorder
    )
    let model = LeaderboardModel(store: store, categorySlug: "no-such", domain: .makeup)
    model.load()
    await model.loadTask?.value
    #expect(model.selectedCategoryID == nil)
    #expect(model.rows.isEmpty)
    #expect(model.isLoading == false)
    // and no board was fetched for a category nobody asked for
    #expect(await recorder.calls.isEmpty)
}

@MainActor
@Test func selectingAPillReloadsForThatCategory() async throws {
    let blush = try category("blush")
    let foundation = try category("foundation")
    let recorder = Recorder()
    let store = recordingStore(categories: [blush, foundation], rows: [], recorder: recorder)
    let model = LeaderboardModel(store: store, categorySlug: "blush", domain: .makeup)
    model.load()
    await model.loadTask?.value
    model.select(categoryID: foundation.id)
    await model.loadTask?.value
    #expect(model.selectedCategoryID == foundation.id)
    let last = try #require(await recorder.calls.last)
    #expect(last.id == foundation.id)
}

// ── the wire words ─────────────────────────────────────────────────────────

@MainActor
@Test func theBoardOpensScopedAndWiresYours() async throws {
    // the frame's default is the scoped board — rank among people whose
    // evidence transfers
    let recorder = Recorder()
    let store = try recordingStore(categories: [category("blush")], rows: [], recorder: recorder)
    let model = LeaderboardModel(store: store, categorySlug: "blush", domain: .makeup)
    #expect(model.scope == .yours)
    model.load()
    await model.loadTask?.value
    let call = try #require(await recorder.calls.first)
    #expect(call.wire == "yours")
    #expect(call.ascending == false)
}

@MainActor
@Test func switchingScopeReloadsWithTheRPCsWordForEveryone() async throws {
    let recorder = Recorder()
    let store = try recordingStore(categories: [category("blush")], rows: [], recorder: recorder)
    let model = LeaderboardModel(store: store, categorySlug: "blush", domain: .makeup)
    model.load()
    await model.loadTask?.value
    model.scope = .everyone
    await model.loadTask?.value
    let last = try #require(await recorder.calls.last)
    #expect(last.wire == "all") // "all" is the RPC's word, never "everyone"
}

@MainActor
@Test func theLowestBoardReloadsAscending() async throws {
    let recorder = Recorder()
    let store = try recordingStore(categories: [category("blush")], rows: [], recorder: recorder)
    let model = LeaderboardModel(store: store, categorySlug: "blush", domain: .makeup)
    model.load()
    await model.loadTask?.value
    model.ascending = true
    await model.loadTask?.value
    let last = try #require(await recorder.calls.last)
    #expect(last.ascending == true)
}

// ── the caption's rule: below min-n says so instead of hiding ──────────────

@MainActor
@Test func rankSkipsUnrankableRowsInsteadOfHidingThem() async throws {
    let ranked1 = try lbRow("first", pct: 0.9, n: 12)
    let thin = try lbRow("thin", pct: nil, n: 3) // wrong side of the gate
    let ranked2 = try lbRow("second", pct: 0.7, n: 8)
    let store = try recordingStore(
        categories: [category("blush")],
        rows: [ranked1, thin, ranked2],
        recorder: Recorder()
    )
    let model = LeaderboardModel(store: store, categorySlug: "blush", domain: .makeup)
    model.load()
    await model.loadTask?.value
    #expect(model.rank(of: ranked1) == 1)
    #expect(model.rank(of: thin) == nil) // "—", the row stays
    #expect(model.rank(of: ranked2) == 2) // the number skips it, not the list
}

// ── the words ──────────────────────────────────────────────────────────────

@MainActor
@Test func evidenceLabelNamesTheCohortByKind() {
    let makeup = LeaderboardModel(store: nil, categorySlug: "blush", domain: .makeup)
    #expect(makeup.evidenceLabel() == "face-offs · your shade")
    makeup.scope = .everyone
    #expect(makeup.evidenceLabel() == "face-offs")
    let hair = LeaderboardModel(store: nil, categorySlug: "stylers", domain: .haircare)
    #expect(hair.evidenceLabel() == "face-offs · your type")
}

@MainActor
@Test func theScopedSegmentSpeaksTheDomainsLanguage() {
    #expect(LeaderboardModel(store: nil, categorySlug: "s", domain: .haircare).yoursOption == "your type")
    #expect(LeaderboardModel(store: nil, categorySlug: "b", domain: .makeup).yoursOption == "your shade")
    #expect(LeaderboardModel(store: nil, categorySlug: "c", domain: .skincare).yoursOption == "your shade")
}

@Test func emptyLineQuotesTheRowsOwnThreshold() {
    #expect(LeaderboardModel.emptyLine(n: 3, needed: 5) == "not enough face-offs yet · 3 of 5")
    // a non-5 threshold reads its own number, not a constant
    #expect(LeaderboardModel.emptyLine(n: 1, needed: 7) == "not enough face-offs yet · 1 of 7")
}

@MainActor
@Test func theFooterReadsTheThresholdOffTheRows() async throws {
    let store = try recordingStore(
        categories: [category("blush")],
        rows: [lbRow("a", pct: 0.9, n: 12, needed: 3)], // wrong side of "always 5"
        recorder: Recorder()
    )
    let model = LeaderboardModel(store: store, categorySlug: "blush", domain: .makeup)
    #expect(model.footerLine.contains("needs 5 face-offs")) // no rows yet → the fallback
    model.load()
    await model.loadTask?.value
    #expect(model.footerLine.contains("needs 3 face-offs")) // the rows' own gate
}

// ── degradation ────────────────────────────────────────────────────────────

@MainActor
@Test func noStoreDegradesQuietlyNotACrash() {
    let model = LeaderboardModel(store: nil, categorySlug: "blush", domain: .makeup)
    model.load()
    #expect(model.rows.isEmpty)
    #expect(model.isLoading == false)
}

@MainActor
@Test func aFailingRowsReadRendersTheEmptyBoard() async throws {
    let blush = try category("blush")
    let store = LeaderboardStore(
        rows: { _, _, _ in throw URLError(.timedOut) },
        categories: { _ in [blush] }
    )
    let model = LeaderboardModel(store: store, categorySlug: "blush", domain: .makeup)
    model.load()
    await model.loadTask?.value
    #expect(model.rows.isEmpty)
    #expect(model.isLoading == false)
}

@MainActor
@Test func imageURLComposesFromBaseAndDegradesToNil() throws {
    let row = try lbRow("a", pct: nil, n: 0)
    let based = LeaderboardModel(
        store: nil, categorySlug: "blush", domain: .makeup,
        imageBase: URL(string: "https://s.test/catalog")
    )
    let bare = LeaderboardModel(store: nil, categorySlug: "blush", domain: .makeup)
    #expect(based.imageURL(for: row.hit) == nil) // no key → mock, never broken
    #expect(bare.imageURL(for: row.hit) == nil)
}

@Test func theDisplayedNIsTheFaceOffCountNotTheUserCount() throws {
    // the first drive's finding: 21 face-offs from 13 users read
    // "13 face-offs" — the label's word and the gate's number are both
    // face-offs, so that is the n a row renders
    let row = try lbRow("a", pct: 0.9, n: 13, faceOffs: 21)
    #expect(LeaderboardModel.n(of: row) == 21)
    #expect(row.nUsers == 13) // still decoded, just not the rendered n
}

// ── the rows decode what 0042 sends ────────────────────────────────────────

@Test func dislikeReasonsRideOnlyWhereTheRPCPutThem() throws {
    let lowest = try lbRow("worst", pct: 0.1, n: 9, reasons: ["creases by 2pm"])
    let best = try lbRow("best", pct: 0.9, n: 9)
    #expect(lowest.dislikeReasons == ["creases by 2pm"])
    #expect(best.dislikeReasons == nil)
    #expect(lowest.isRankable && best.isRankable)
}
