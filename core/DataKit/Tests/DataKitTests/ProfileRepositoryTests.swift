import Foundation
import Testing
@testable import DataKit

// Pure rules ProfileRepository encodes. RLS (`profiles_own`) and the minor
// default are proven by the pgTAP suite against real Postgres — these cover
// the Swift-side decisions pgTAP cannot see. Fixtures sit on both sides of
// every precondition (the session-12 rule).

private func draft(
    birth: String = "2001-07",
    domains: [Domain] = [.makeup, .skincare],
    tone: Int? = nil,
    hair: String? = nil
) -> ProfileDraft {
    ProfileDraft(birthYearMonth: birth, domains: domains, toneBand: tone, hairPattern: hair)
}

@Test func aValidDraftHasNoInvalidField() {
    #expect(ProfileDraft.firstInvalidField(draft(tone: 6, hair: "3b")) == nil)
    // and the optionals absent is equally valid — the quiz's design is that
    // most fields come after you're in
    #expect(ProfileDraft.firstInvalidField(draft()) == nil)
}

@Test func theBirthMonthShapeMatchesTheCheckConstraint() {
    // wrong side of the shape, each way the wheel could go wrong
    #expect(ProfileDraft.firstInvalidField(draft(birth: "2001-13")) == "birthday")
    #expect(ProfileDraft.firstInvalidField(draft(birth: "2001-00")) == "birthday")
    #expect(ProfileDraft.firstInvalidField(draft(birth: "01-07")) == "birthday")
    #expect(ProfileDraft.firstInvalidField(draft(birth: "2001-7")) == "birthday")
    #expect(ProfileDraft.firstInvalidField(draft(birth: "2001-07")) == nil)
}

@Test func birthYearMonthComposesTheWireShapeOrRefuses() {
    #expect(ProfileDraft.birthYearMonth(year: 2001, month: 7) == "2001-07")
    #expect(ProfileDraft.birthYearMonth(year: 2001, month: 12) == "2001-12")
    #expect(ProfileDraft.birthYearMonth(year: 2001, month: 13) == nil)
    #expect(ProfileDraft.birthYearMonth(year: 2001, month: 0) == nil)
    #expect(ProfileDraft.birthYearMonth(year: 1930, month: 1) == "1930-01")
}

@Test func atLeastOneDomainAlways() {
    // the quiz never lets the last domain deselect; the draft holds the same
    // line so a broken caller fails as words, not as a confusing empty app
    #expect(ProfileDraft.firstInvalidField(draft(domains: [])) == "domains")
    #expect(ProfileDraft.firstInvalidField(draft(domains: [.fragrance])) == nil)
}

@Test func toneBandMatchesTheCheckConstraint() {
    #expect(ProfileDraft.firstInvalidField(draft(tone: 0)) == "tone band")
    #expect(ProfileDraft.firstInvalidField(draft(tone: 11)) == "tone band")
    #expect(ProfileDraft.firstInvalidField(draft(tone: 1)) == nil)
    #expect(ProfileDraft.firstInvalidField(draft(tone: 10)) == nil)
}

@Test func hairPatternMatchesTheCheckConstraint() {
    #expect(ProfileDraft.firstInvalidField(draft(hair: "3b")) == nil)
    #expect(ProfileDraft.firstInvalidField(draft(hair: "4c")) == nil)
    #expect(ProfileDraft.firstInvalidField(draft(hair: "5a")) == "hair type")
    #expect(ProfileDraft.firstInvalidField(draft(hair: "3d")) == "hair type")
    #expect(ProfileDraft.firstInvalidField(draft(hair: "curly")) == "hair type")
}

@Test func skinTypeWireValuesMatchTheDatabaseEnum() {
    // a mismatch is a silent write the check constraint rejects
    #expect(Set(SkinType.allCases.map(\.rawValue)) == ["oily", "dry", "combo", "sensitive"])
}

@Test func theRowEncodesSnakeCaseAndOmitsBrandAffinities() throws {
    let row = draft(tone: 6, hair: "3b").row(userID: UUID())
    let data = try JSONEncoder().encode(row)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["birth_year_month"] as? String == "2001-07")
    #expect(json["tone_band"] as? Int == 6)
    #expect(json["hair_pattern"] as? String == "3b")
    #expect(json["domains"] as? [String] == ["makeup", "skincare"])
    // absent, deliberately: an upsert writing {} over a later brands answer
    // would erase it — absent columns keep their values
    #expect(json["brand_affinities"] == nil)
    #expect(json["user_id"] != nil)
}

@Test func theProfileDecodesTheTableRow() throws {
    let raw = Data("""
    {"user_id":"\(UUID().uuidString)","display_name":null,"avatar_seed":null,
     "timezone":"America/New_York","birth_year_month":"1999-03",
     "domains":["makeup","haircare"],"skin_type":"combo","concerns":["redness"],
     "tone_band":5,"hair_pattern":"3b","climate":null,"brand_affinities":[],
     "created_at":"2026-08-29T00:00:00Z","updated_at":"2026-08-29T00:00:00Z"}
    """.utf8)
    let profile = try JSONDecoder().decode(Profile.self, from: raw)
    #expect(profile.birthYearMonth == "1999-03")
    #expect(profile.skinType == .combo)
    #expect(profile.domains == [.makeup, .haircare])
    #expect(profile.toneBand == 5)
    #expect(profile.hairPattern == "3b")
}

// ── the second opening (Sean, Aug 30): brands + the anchor read ────────────

@Test func brandsEncodeOnlyWhenTheDraftCarriesAnAnswer() throws {
    // both sides of the never-erase design: nil omits the key entirely
    // (onboarding's write leaves the column untouched); an answer — even
    // the empty list — carries it (the tune screen clearing brands is an
    // answer too)
    let unasked = draft().row(userID: UUID())
    let unaskedJSON = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(unasked)) as? [String: Any]
    )
    #expect(unaskedJSON["brand_affinities"] == nil)

    var tuned = draft()
    tuned.brandAffinities = ["rhode", "kosas"]
    let tunedJSON = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(tuned.row(userID: UUID()))) as? [String: Any]
    )
    #expect(tunedJSON["brand_affinities"] as? [String] == ["rhode", "kosas"])

    var cleared = draft()
    cleared.brandAffinities = []
    let clearedJSON = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(cleared.row(userID: UUID()))) as? [String: Any]
    )
    #expect(clearedJSON["brand_affinities"] as? [String] == [])
}

@Test func theAnchorFactDecodesTheViewRow() throws {
    let raw = Data("""
    {"user_id":"\(UUID().uuidString)","variant_id":"\(UUID().uuidString)",
     "fit":"just_right","season":null,"captured_at":null}
    """.utf8)
    let fact = try JSONDecoder().decode(ShadeAnchorFact.self, from: raw)
    #expect(fact.fit == .justRight)
    #expect(fact.capturedAt == nil)
}

@Test func thePhotoKeyWriteSendsItsTwoColumnsAndNeverTheKeyToALog() throws {
    // The StateUpdate discipline for the pfp (GLO-272): exactly photo_r2_key
    // + the hand stamp (profiles has no touch trigger — probed, pg_trigger
    // is empty for it). A payload that grew display_name would let a photo
    // save silently rename the account.
    let update = ProfileRepository.PhotoKeyUpdate(
        photoR2Key: "users/u/profile/abc.jpg", updatedAt: "2026-08-31T00:00:00Z"
    )
    let data = try JSONEncoder().encode(update)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    #expect(object.keys.sorted() == ["photo_r2_key", "updated_at"])
}
