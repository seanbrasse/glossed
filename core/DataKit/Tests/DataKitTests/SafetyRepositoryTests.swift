import Foundation
import Testing
@testable import DataKit

// The vocabularies and rules the Swift side encodes. Enforcement — blocks
// severing follows, the minor lock on badges, who may read what — is proven by
// pgTAP against real Postgres and RLS.

@Test func reportReasonsMatchTheDatabaseCheckConstraint() {
    // A value not in the constraint is a write that fails at runtime, on the
    // report sheet, after the user has typed an explanation.
    #expect(Set(ReportReason.allCases.map(\.rawValue)) == [
        "impersonation", "harassment", "spam", "nudity",
        "ai_generated", "underage", "self_harm", "other"
    ])
}

@Test func reportSubjectsMatchTheEnum() {
    #expect(Set(ReportSubject.allCases.map(\.rawValue)) == [
        "profile", "handle", "bio", "collection", "routine", "swatch", "linked_social"
    ])
}

@Test func theTwoEscalationReasonsExistAsFirstClassChoices() {
    // runbook.md §1 gives underage and self_harm a same-day human path. They
    // have to be selectable for that routing to ever happen — burying them
    // under "something else" would make the queue unable to see them.
    #expect(ReportReason.allCases.contains(.underage))
    #expect(ReportReason.allCases.contains(.selfHarm))
}

@Test func reportLabelsAreLowercaseAndPlain() {
    // Lowercase is the house voice. Plainness matters more here than anywhere:
    // someone reporting harassment should not have to decode a category name.
    for reason in ReportReason.allCases {
        #expect(reason.label == reason.label.lowercased())
        #expect(!reason.label.isEmpty)
    }
    #expect(ReportReason.underage.label.contains("under 13"))
}

@Test func allFivePublicTextKindsExist() {
    // Every user-authored string another user can see goes through
    // public_texts. A kind missing here is a surface that publishes unmoderated
    // text — which is the exact failure the single table exists to prevent.
    #expect(Set(PublicTextKind.allCases.map(\.rawValue)) == [
        "bio", "handle", "collection_title", "routine_title", "linked_social"
    ])
}

@Test func onlyApprovedTextIsVisibleToOthers() {
    // §3.2's render rule, in the type. Pending must NOT read as visible — the
    // window between the write and the review is where a naive design leaks.
    let approved = PublicText(kind: .bio, subjectID: nil, body: "hi", state: .approved)
    let pending = PublicText(kind: .bio, subjectID: nil, body: "hi", state: .pending)
    let rejected = PublicText(kind: .bio, subjectID: nil, body: "hi", state: .rejected)
    #expect(approved.isVisibleToOthers)
    #expect(!pending.isVisibleToOthers)
    #expect(!rejected.isVisibleToOthers)
}

@Test func publicTextDecodesFromTheWireShape() throws {
    let json = Data("""
    {"kind":"routine_title","subject_id":"11111111-1111-4111-8111-111111111111",
     "body":"morning","state":"pending"}
    """.utf8)
    let text = try JSONDecoder().decode(PublicText.self, from: json)
    #expect(text.kind == .routineTitle)
    #expect(text.state == .pending)
    #expect(!text.isVisibleToOthers)
}

@Test func everyBadgeDefaultsOff() {
    // All three default false because they are the ONLY path by which skin
    // type, the anchor variant and hair pattern reach another human (§3.4).
    // A default-on badge would publish Regulated data nobody chose to publish.
    let badges = ProfileBadges()
    for badge in ProfileBadges.Badge.allCases {
        #expect(!badges.isOn(badge))
    }
}

@Test func badgeKeysMatchTheColumnNames() {
    // The raw value IS the column written by setBadge. A mismatch writes a
    // column that does not exist, or worse, the wrong one.
    #expect(ProfileBadges.Badge.skinType.rawValue == "show_skin_type")
    #expect(ProfileBadges.Badge.anchor.rawValue == "show_anchor")
    #expect(ProfileBadges.Badge.hairPattern.rawValue == "show_hair_pattern")
}

@Test func badgeLookupReadsTheRightFlag() {
    // Distinct values per badge, so a case reading the wrong property shows up.
    let badges = ProfileBadges(showSkinType: true, showAnchor: false, showHairPattern: true)
    #expect(badges.isOn(.skinType))
    #expect(!badges.isOn(.anchor))
    #expect(badges.isOn(.hairPattern))
}

@Test func badgesDecodeFromTheWireShape() throws {
    let json = Data("""
    {"show_skin_type":true,"show_anchor":false,"show_hair_pattern":false}
    """.utf8)
    let badges = try JSONDecoder().decode(ProfileBadges.self, from: json)
    #expect(badges.showSkinType)
    #expect(!badges.showAnchor)
}
