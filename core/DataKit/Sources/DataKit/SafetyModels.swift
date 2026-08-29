import Foundation
import Supabase

/// What a report is about. Mirrors `report_subject`.
public enum ReportSubject: String, Codable, Sendable, CaseIterable {
    case profile, handle, bio, collection, routine, swatch
    case linkedSocial = "linked_social"
}

/// Why. Mirrors the `reports.reason` check constraint.
///
/// `underage` and `selfHarm` are not ordinary categories: `docs/runbook.md` §1
/// gives both a same-day human escalation and forbids actioning the content or
/// asking the user to confirm their age. Nothing here treats them differently —
/// that is the runbook's job, and the reason exists so the queue can route it.
public enum ReportReason: String, Codable, Sendable, CaseIterable {
    case impersonation, harassment, spam, nudity
    case aiGenerated = "ai_generated"
    case underage
    case selfHarm = "self_harm"
    case other

    /// Lowercase UI copy for the report sheet's rows.
    public var label: String {
        switch self {
        case .impersonation: "pretending to be someone"
        case .harassment: "harassment or bullying"
        case .spam: "spam or a scam"
        case .nudity: "nudity or sexual content"
        case .aiGenerated: "ai-generated, presented as real"
        case .underage: "this person may be under 13"
        case .selfHarm: "self-harm"
        case .other: "something else"
        }
    }
}

/// The five kinds of user-authored text another user can see. Mirrors
/// `public_text_kind`. Every one goes through `public_texts` — a
/// `moderation_state` sprinkled across four tables guarantees the fifth is
/// forgotten.
public enum PublicTextKind: String, Codable, Sendable, CaseIterable {
    case bio, handle
    case collectionTitle = "collection_title"
    case routineTitle = "routine_title"
    case linkedSocial = "linked_social"
}

/// Where a piece of public text is in review. Mirrors `moderation_state`.
public enum ModerationState: String, Codable, Sendable {
    case pending, approved, rejected
}

/// One row of `public_texts`, as its author sees it.
public struct PublicText: Codable, Sendable, Equatable {
    public let kind: PublicTextKind
    public let subjectID: UUID?
    public let body: String
    public let state: ModerationState

    enum CodingKeys: String, CodingKey {
        case kind
        case subjectID = "subject_id"
        case body, state
    }

    /// Whether anyone else can see this yet. A public surface reads only
    /// `approved` (§3.2), so a pending edit renders the previously approved
    /// body or nothing — never the pending text. The author's own screen shows
    /// their draft with this flag to explain why nobody else does.
    public var isVisibleToOthers: Bool {
        state == .approved
    }
}

/// The badges a user has chosen to publish. All default false: these are the
/// ONLY path by which `skin_type`, the anchor variant and `hair_pattern` reach
/// another human (§3.4), which is why nothing else in the app may publish them.
public struct ProfileBadges: Codable, Sendable, Equatable {
    public let showSkinType: Bool
    public let showAnchor: Bool
    public let showHairPattern: Bool

    enum CodingKeys: String, CodingKey {
        case showSkinType = "show_skin_type"
        case showAnchor = "show_anchor"
        case showHairPattern = "show_hair_pattern"
    }

    public init(showSkinType: Bool = false, showAnchor: Bool = false, showHairPattern: Bool = false) {
        self.showSkinType = showSkinType
        self.showAnchor = showAnchor
        self.showHairPattern = showHairPattern
    }

    /// Which badge governs which fact. Publishing any of these three anywhere
    /// else in the app is a second path around the opt-in.
    public enum Badge: String, Sendable, CaseIterable {
        case skinType = "show_skin_type"
        case anchor = "show_anchor"
        case hairPattern = "show_hair_pattern"
    }

    public func isOn(_ badge: Badge) -> Bool {
        switch badge {
        case .skinType: showSkinType
        case .anchor: showAnchor
        case .hairPattern: showHairPattern
        }
    }
}
