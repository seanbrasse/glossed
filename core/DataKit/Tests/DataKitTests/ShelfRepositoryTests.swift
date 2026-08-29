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

// MARK: - The GLO-16 / GLO-87 opening (chips, notes, like state)

@Test func clearingANoteEncodesAnExplicitNullRatherThanDroppingTheKey() throws {
    // The trap this guards: Swift synthesizes `encodeIfPresent` for optional
    // properties, so a synthesized encoder emits `{}` for a nil note. PostgREST
    // treats a PATCH with no keys as a successful no-op — the request returns
    // 2xx, every layer above reports success, and the note is still there.
    let cleared = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(NoteUpdate(note: nil))
    ) as? [String: Any]
    #expect(cleared?.keys.contains("note") == true)
    #expect(cleared?["note"] is NSNull)

    let set = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(NoteUpdate(note: "smells like pennies"))
    ) as? [String: Any]
    #expect(set?["note"] as? String == "smells like pennies")
}

@Test func clearingLikeStateEncodesAnExplicitNullAndTheColumnName() throws {
    let cleared = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(LikeStateUpdate(likeState: nil))
    ) as? [String: Any]
    #expect(cleared?.keys.contains("like_state") == true)
    #expect(cleared?["like_state"] is NSNull)

    let disliked = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(LikeStateUpdate(likeState: LikeState.disliked.rawValue))
    ) as? [String: Any]
    #expect(disliked?["like_state"] as? Int == -1)
}

@Test func likeStateRawValuesMatchTheColumnsCheckConstraint() {
    // `like_state smallint check (like_state between -1 and 1)` — 0002. A case
    // added with any other raw value would fail at write time, not compile time.
    #expect(LikeState.allCases.map(\.rawValue).sorted() == [-1, 0, 1])
}

@Test func aMissingLikeStateDecodesAsNoAnswerRatherThanNeutral() throws {
    // Never-asked and asked-and-shrugged are different facts, and the column is
    // nullable precisely so they stay different.
    let unanswered = try JSONDecoder().decode(LikeStateRow.self, from: Data(#"{"like_state":null}"#.utf8))
    #expect(unanswered.likeState == nil)

    let shrugged = try JSONDecoder().decode(LikeStateRow.self, from: Data(#"{"like_state":0}"#.utf8))
    #expect(shrugged.likeState == .neutral)
}

@Test func appliedChipDecodesThePostgrestEmbeddedResourceShape() throws {
    // The embedded row arrives under the joined TABLE's name, not the property's
    // — if `chips(itemID:)`'s select list and this key ever drift, the sheet
    // comes back empty rather than wrong, which is the failure hardest to spot.
    let json = Data("""
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "week": 3,
      "freetext": null,
      "experience_chips": {
        "id": "22222222-2222-2222-2222-222222222222",
        "domain": "skincare",
        "category_id": null,
        "slug": "broke-me-out",
        "label": "broke me out",
        "valence": "dislike"
      }
    }
    """.utf8)

    let applied = try JSONDecoder().decode(AppliedChip.self, from: json)
    #expect(applied.week == 3)
    #expect(applied.freetext == nil)
    #expect(applied.chip.slug == "broke-me-out")
    #expect(applied.chip.valence == .dislike)
    #expect(applied.chip.domain == .skincare)
    // Null category_id is the domain-wide chip — not a decode failure.
    #expect(applied.chip.categoryID == nil)
}

@Test func experienceChipDecodesACategoryScopedRow() throws {
    let json = Data("""
    {
      "id": "33333333-3333-3333-3333-333333333333",
      "domain": "makeup",
      "category_id": "44444444-4444-4444-4444-444444444444",
      "slug": "oxidized",
      "label": "oxidized",
      "valence": "dislike"
    }
    """.utf8)

    let chip = try JSONDecoder().decode(ExperienceChip.self, from: json)
    #expect(chip.categoryID?.uuidString == "44444444-4444-4444-4444-444444444444")
    #expect(chip.label == "oxidized")
}

@Test func chipValenceCoversExactlyWhatTheEnumTypeDeclares() {
    // `create type chip_valence as enum ('like', 'dislike')` — 0001.
    #expect(Set(ChipValence.allCases.map(\.rawValue)) == ["like", "dislike"])
}
