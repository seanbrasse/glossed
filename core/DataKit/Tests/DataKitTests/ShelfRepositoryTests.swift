import Foundation
import Supabase
import Testing
@testable import DataKit

// Pure rules the shelf repository encodes. Query behavior itself is proven by the
// pgTAP suite against real Postgres + RLS, which is the actual security
// boundary; these cover the Swift-side logic that pgTAP cannot see.

@Test func weekOneIsTheFirstSevenDays() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let day = 86400.0
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start) == 1)
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start + 6 * day) == 1)
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start + 7 * day) == 2)
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start + 69 * day) == 10)
}

@Test func weekIsNilWithoutAStartDate() {
    // Makeup and fragrance have nothing to wear in, so their chips carry no week.
    #expect(ShelfRepository.week(startedOn: nil, loggedOn: Date()) == nil)
}

@Test func weekIgnoresLogsBeforeTheStartDate() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(ShelfRepository.week(startedOn: start, loggedOn: start - 86400) == nil)
}

@Test func logDraftGeneratesADistinctIdempotencyKeyPerDraft() {
    let variant = UUID()
    #expect(LogDraft(variantID: variant).clientID != LogDraft(variantID: variant).clientID)
    // …but a caller-supplied key is preserved, so a retry resolves to one row.
    let fixed = UUID()
    #expect(LogDraft(variantID: variant, clientID: fixed).clientID == fixed)
}

@Test func shelfRowDecodesEveryColumnTheViewReturns() throws {
    // These key names are `user_shelf_items`' columns. If the two drift, the
    // shelf comes back empty rather than wrong, which is the failure that is
    // hardest to notice — so the whole row is spelled out here.
    let raw = Data(#"""
    {"user_item_id":"00000000-0000-0000-0000-0000000000a1",
     "variant_id":"00000000-0000-0000-0000-0000000000a2",
     "product_id":"00000000-0000-0000-0000-0000000000a3",
     "product_name":"soft pinch liquid blush","brand_name":"rare beauty",
     "category_slug":"blush","category_label":"blush","domain":"makeup",
     "scope":"canonical","benefit_line":"one dot, blends forever",
     "variant_label":"joy · 7.5ml","height_mm":70,"status":"own",
     "started_on":"2026-08-01","note":null,"cutout_r2_key":null,
     "logged_at":"2026-08-01T12:00:00Z","rank_position":2,"ranked_in_category":5,"is_anchor":false,
     "catalog_image_key":"00000000-0000-0000-0000-0000000000a2/cut512.png",
     "catalog_image_width":219,"catalog_image_height":372,"size_ml":236}
    """#.utf8)
    let row = try PostgrestClient.Configuration.jsonDecoder.decode(ShelfRow.self, from: raw)

    #expect(row.catalogImageKey == "00000000-0000-0000-0000-0000000000a2/cut512.png")
    #expect(row.catalogImageWidth == 219)
    #expect(row.catalogImageHeight == 372)
    #expect(row.sizeML == 236)
    #expect(row.id == row.userItemID)
    #expect(row.brandName == "rare beauty")
    #expect(row.categoryLabel == "blush")
    #expect(row.variantLabel == "joy · 7.5ml")
    #expect(row.heightMM == 70)
    #expect(row.scope == .canonical)
    #expect(row.rankPosition == 2)
    #expect(row.rankedInCategory == 5)
    #expect(row.isAnchor == false)
    // The one that used to be impossible: `started_on` is a Postgres `date`,
    // and the platform decoder parses timestamps only. Bound straight to
    // `Date?` this whole row threw.
    #expect(row.startedOn == Calendar(identifier: .gregorian)
        .date(from: DateComponents(timeZone: .current, year: 2026, month: 8, day: 1)))
}

@Test func aPostgresDateDecodesWhereThePlatformDecoderCannot() throws {
    // Proof of the defect this fixes, stated as the platform's own behaviour:
    // the supabase decoder wants year-month-day *and a time*, so a bare
    // calendar day throws. Every `date` column in the schema is one of these.
    struct Naive: Decodable { let startedOn: Date? }
    #expect(throws: DecodingError.self) {
        _ = try PostgrestClient.Configuration.jsonDecoder
            .decode(Naive.self, from: Data(#"{"startedOn":"2026-08-01"}"#.utf8))
    }
    let item = try PostgrestClient.Configuration.jsonDecoder.decode(UserItem.self, from: Data(#"""
    {"id":"00000000-0000-0000-0000-0000000000c1",
     "user_id":"00000000-0000-0000-0000-0000000000c2",
     "variant_id":"00000000-0000-0000-0000-0000000000c3",
     "status":"own","started_on":"2026-08-01","note":null,"cutout_r2_key":null}
    """#.utf8))
    let started = try #require(item.startedOn)
    #expect(ShelfRepository.week(startedOn: started, loggedOn: started) == 1)
}

@Test func anUnrankedRowHasNoPositionRatherThanZero() throws {
    // A category under its unlock threshold has no order yet. Reporting that as
    // position 0 is a claim the data cannot support, and it sorts first.
    let raw = Data(#"""
    {"user_item_id":"00000000-0000-0000-0000-0000000000a1",
     "variant_id":"00000000-0000-0000-0000-0000000000a2",
     "product_id":"00000000-0000-0000-0000-0000000000a3",
     "product_name":"hand cream","brand_name":"glossier",
     "category_slug":"blush","category_label":"blush","domain":"makeup",
     "scope":"personal","benefit_line":null,"variant_label":null,
     "height_mm":null,"status":"want_to_try","started_on":null,"note":null,
     "cutout_r2_key":null,"logged_at":"2026-08-01T12:00:00Z",
     "rank_position":null,"ranked_in_category":0,"is_anchor":true}
    """#.utf8)
    let row = try PostgrestClient.Configuration.jsonDecoder.decode(ShelfRow.self, from: raw)

    #expect(row.rankPosition == nil)
    #expect(row.heightMM == nil)
    #expect(row.variantLabel == nil)
    #expect(row.status == .wantToTry)
    #expect(row.scope == .personal)
    #expect(row.isAnchor)
}

@Test func aFitCaptureEncodesTheRPCArgumentNames() throws {
    // The set is sorted on the wire: identical captures must encode
    // identically, and Set iteration order would break that.
    let params = CaptureFitParams(
        userItemID: "50000000-0000-0000-0000-000000000021",
        fits: Set<Fit>([.tooPink, .tooLight]).map(\.rawValue).sorted(),
        season: nil
    )
    let data = try JSONEncoder().encode(params)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["p_user_item_id"] as? String == "50000000-0000-0000-0000-000000000021")
    #expect(json["p_fits"] as? [String] == ["too_light", "too_pink"])
}
