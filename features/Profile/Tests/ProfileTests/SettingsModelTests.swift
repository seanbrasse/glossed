import DataKit
import Foundation
import Testing
@testable import Profile

// Settings (GLO-213). The rule under most of these: a row says what we can
// read, or says it is unset. It never borrows the frame's example value.

private func profile(
    name: String? = "maya k.",
    skin: SkinType? = .combo,
    tone: Int? = 6,
    hair: String? = "3b",
    domains: [Domain] = [.makeup, .skincare],
    birth: String = "1998-04"
) throws -> Profile {
    let json = """
    {"user_id":"\(UUID().uuidString)","display_name":\(name
        .map { "\"\($0)\"" } ?? "null"),"birth_year_month":"\(birth)",
     "domains":[\(domains.map { "\"\($0.rawValue)\"" }.joined(separator: ","))],
     "skin_type":\(skin.map { "\"\($0.rawValue)\"" } ?? "null"),
     "concerns":[],"tone_band":\(tone.map(String.init) ?? "null"),
     "hair_pattern":\(hair.map { "\"\($0)\"" } ?? "null"),
     "climate":null,"brand_affinities":[]}
    """
    return try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
}

@MainActor
@Test func everyRowIsFilledFromTheProfileRatherThanTheFrame() throws {
    let rows = try SettingsModel.rows(profile: profile(), anchor: nil, bio: nil)
    let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.value) })
    #expect(byID["skin"] == "tone 6 · combo")
    #expect(byID["hair"] == "3b")
    #expect(byID["domains"] == "makeup · skincare")
}

@MainActor
@Test func anUnansweredFactIsNilRatherThanTheFramesExample() throws {
    // The frame reads "tone 6 · warm · combo". A real account that never
    // answered the quiz has none of that, and printing the fixture would be a
    // settings screen describing somebody else.
    let rows = try SettingsModel.rows(
        profile: profile(name: nil, skin: nil, tone: nil, hair: nil, domains: []),
        anchor: nil, bio: ""
    )
    for row in rows where row.id != "birthday" {
        #expect(row.value == nil, "\(row.id) should be unset, not invented")
    }
}

@MainActor
@Test func thereIsNoNotificationsRow() throws {
    // The frame shows "rank nudges on". There is no notification system,
    // nothing to toggle, and nothing that would make the row true. A settings
    // row for a feature that does not exist is a promise — GLO-189's mistake.
    #expect(try !SettingsModel.rows(profile: profile(), anchor: nil, bio: nil).contains { $0.id == "notifications" })
}

@MainActor
@Test func birthdayIsMonthAndYearBecauseThatIsAllThereIs() throws {
    // The day is dropped before the write (domain.md §6). Rendering the
    // frame's "04 / 1998" shape is right only because it carries no day —
    // anything with one would claim precision the database refuses to keep.
    #expect(try SettingsModel.birthdayLine(profile(birth: "1998-04")) == "04 / 1998")
    #expect(SettingsModel.birthdayLine(nil) == nil)
}

// MARK: - GLO-257: the birthday is not editable, and settings is categories

@MainActor
@Test func theBirthdayIsRenderedAndNeverOffered() throws {
    // It is the 18+ gate — "18+ gate and recs only, never on the profile" —
    // and a gate the gated party can edit is not a gate. No affordance, not a
    // disabled one.
    let rows = try SettingsModel.rows(profile: profile(), anchor: nil, bio: "")
    let birthday = try #require(rows.first { $0.id == "birthday" })
    #expect(birthday.value == "04 / 1998")
    #expect(!birthday.isEditable)
}

@MainActor
@Test func onlyTheNameAndTheBioCanBeChangedHere() throws {
    // Everything else states a fact set elsewhere — onboarding, the tune
    // sheet, the shelf — or, for the birthday, set nowhere at all.
    let rows = try SettingsModel.rows(profile: profile(), anchor: nil, bio: "")
    #expect(rows.filter(\.isEditable).map(\.id) == ["name", "bio"])
}

@MainActor
@Test func everyRowLandsInExactlyOneCategory() throws {
    // A row that falls out of the grouping vanishes from the screen. This is
    // the test that catches a new row nobody filed.
    let rows = try SettingsModel.rows(profile: profile(), anchor: nil, bio: "")
    let grouped = SettingsModel.categories(rows).flatMap(\.rows).map(\.id)
    #expect(Set(grouped) == Set(rows.map(\.id)))
    #expect(grouped.count == rows.count)
}

@MainActor
@Test func theTwoCategoriesSplitWhatPeopleSeeFromWhatTheAppKnows() throws {
    // tech/02 §3.3: `public_profile` returns display_name and bio. §3.4: the
    // body facts reach another person only as an opt-in badge, published from
    // the privacy screen — so they are answers, not profile fields.
    let categories = try SettingsModel.categories(
        SettingsModel.rows(profile: profile(), anchor: nil, bio: "")
    )
    #expect(categories.map(\.id) == ["profile", "personal"])
    #expect(categories[0].rows.map(\.id) == ["name", "bio"])
    #expect(categories[1].rows.map(\.id) == ["skin", "anchor", "hair", "domains", "birthday"])
}

@MainActor
@Test func aCategoryWithNothingInItIsNotShown() throws {
    // The bio row is omitted when there is no editor to open (GLO-213). With
    // no name either, `your profile` has nothing to descend into and the root
    // does not offer a door onto an empty room.
    let rows = try SettingsModel.rows(profile: profile(name: nil), anchor: nil, bio: nil)
        .filter { $0.id != "name" }
    #expect(SettingsModel.categories(rows).map(\.id) == ["personal"])
}

@MainActor
@Test func theRootCardSaysWhatIsInsideBeforeYouOpenIt() throws {
    // The preview is the affordance — there is no chevron, because the kit's
    // `ICONS.chevronRight` is not ported and an SF Symbol is GLO-64 exactly.
    let categories = try SettingsModel.categories(
        SettingsModel.rows(profile: profile(), anchor: nil, bio: "")
    )
    #expect(categories[0].summary == "your name · your bio")
    #expect(categories[1].summary == "skin profile · shade anchor · hair type · what you buy · birthday")
}

@MainActor
@Test func theAnchorRowNamesTheFitNotAShadeItCannotRead() throws {
    // user_shade_anchor carries a variant id and a fit, not a brand or shade
    // name. The frame's "fenty 240 · fit logged" would need a catalog lookup
    // this screen does not do, and inventing the half we cannot read is worse
    // than naming the half we can.
    let json = """
    {"variant_id":"\(UUID().uuidString)","fit":"just_right","captured_at":null}
    """
    let anchor = try JSONDecoder().decode(ShadeAnchorFact.self, from: Data(json.utf8))
    #expect(SettingsModel.anchorLine(anchor) == "fit logged · just right")
    #expect(SettingsModel.anchorLine(nil) == nil)
}

@MainActor
@Test func theNameRowIsFirstAndCarriesWhatIsSet() throws {
    let rows = try SettingsModel.rows(profile: profile(), anchor: nil, bio: nil)
    #expect(rows.first?.id == "name")
    #expect(rows.first?.value == "maya k.")
}

@MainActor
@Test func savingANameCarriesEveryOtherFieldForward() async throws {
    // GLO-215: saveProfile upserts the WHOLE row, and `concerns` is
    // non-optional with a default of [] — so a draft that forgets it erases
    // the user's skin concerns and the compiler says nothing. This asserts the
    // editor's store carries them, because the type will not.
    final class Captured: @unchecked Sendable {
        var draft: ProfileDraft?
    }
    let captured = Captured()
    let existing = try profile()
    let repository = SettingsStore(
        profile: { existing },
        anchor: { nil },
        signOut: {},
        saveDisplayName: { name in
            captured.draft = ProfileDraft(
                birthYearMonth: existing.birthYearMonth,
                domains: existing.domains,
                skinType: existing.skinType,
                toneBand: existing.toneBand,
                hairPattern: existing.hairPattern,
                concerns: existing.concerns,
                climate: existing.climate,
                displayName: name,
                brandAffinities: nil
            )
        }
    )
    try await repository.saveDisplayName("renamed")
    let draft = try #require(captured.draft)
    #expect(draft.displayName == "renamed")
    #expect(draft.birthYearMonth == existing.birthYearMonth)
    #expect(draft.domains == existing.domains)
    #expect(draft.concerns == existing.concerns)
    // nil, never [] — nil omits the key and leaves brands alone; [] is a real
    // answer meaning "cleared" and would wipe them.
    #expect(draft.brandAffinities == nil)
}

@MainActor
@Test func theBioRowIsOmittedWhenThereIsNoEditorToOpen() throws {
    // A store built without a bio editor has no row rather than a row that
    // opens nothing — the same reason `notifications` is absent.
    #expect(try !SettingsModel.rows(profile: profile(), anchor: nil, bio: nil)
        .contains { $0.id == "bio" })
    let withEditor = try SettingsModel.rows(profile: profile(), anchor: nil, bio: "soft glam, mostly")
    #expect(withEditor.first { $0.id == "bio" }?.value == "soft glam, mostly")
}
