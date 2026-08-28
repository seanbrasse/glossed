import Foundation

// The Phase 1 event registry — docs/tech/06 §3, as a compiler-checked enum.
//
// The rules the type system enforces, so review does not have to:
//
// - **No ad-hoc names.** An event is a case here or it does not exist; the
//   wire name is derived in one switch the compiler keeps exhaustive.
// - **Identifiers, not values.** Props are ids, enums, counts and booleans.
//   There is no `String` prop constructor — the one string-shaped prop
//   (`search_performed`'s query) is a salted hash by construction, because the
//   raw query already has a home in `failed_searches` and does not belong in
//   analytics twice.
// - **Regulated data never rides along** (domain.md §5). Nothing here can
//   carry a note, a photo, a birthday, or a body fact; cohort joins happen
//   server-side against `user_facts`, not in props.

/// Every event Phase 1 can emit. Adding a case is a PR to this enum *and* the
/// tech/06 registry table — an event without a standing question it answers
/// gets rejected in review (tech/06 §7).
public enum Event: Sendable, Equatable {
    // Onboarding
    case onbStepViewed(step: String, branch: OnboardingBranch?)
    case onbStepCompleted(step: String, branch: OnboardingBranch?)
    case onbAnchorCaptured(brandID: UUID, variantID: UUID, fit: String)
    case onbPayoffShown(exactShadeCount: Int, evidenceBacked: Bool)

    // Catalog
    case searchPerformed(queryHash: String, domain: String?, hit: Bool, resultCount: Int, source: SearchSource)
    case itemLogged(variantID: UUID, categoryID: UUID, source: LogSource, scope: String)

    // Journal
    case chipApplied(chipID: UUID, kind: String, week: Int?)
    case fitCaptured(fits: [String])
    case faceoffCompleted(categoryID: UUID, sessionLength: Int)
    case faceoffSkipped(categoryID: UUID, sessionLength: Int)

    // Surfaces
    case shelfViewed
    case productViewed(productID: UUID)
    case leaderboardViewed(categoryID: UUID, scope: String)

    // Ingest paths
    case importCompleted(source: String, lines: Int, matched: Int, toLadder: Int)
    case shareInReceived(sourceHost: String, resolved: Bool)
    case cutoutCaptured(confidenceBand: String, retake: Bool)
    case exportGenerated(itemCount: Int)

    // Recommendations (tap-through and dismissal only — never dwell)
    case recImpression(slot: RecSlot, variantID: UUID)
    case recTapped(slot: RecSlot, variantID: UUID)
    case recDismissed(slot: RecSlot, variantID: UUID, reason: String?)

    // Failure + safety surfaces
    case errorShown(code: String, supportReference: String)
    case restrictedActionBlocked(surface: String, action: String)
}

public enum OnboardingBranch: String, Sendable {
    case hair, palette
}

public enum SearchSource: String, Sendable {
    case onboarding = "onb"
    case ladder
    case discover
}

public enum LogSource: String, Sendable {
    case search, barcode, photo
    case shareIn = "share_in"
    case importList = "import"
    case ladderCreate = "ladder_create"
}

public enum RecSlot: String, Sendable {
    case stage0, picked, crosswalk, exploration
}

public extension Event {
    /// The wire name: `object_action`, lowercase snake, past tense (tech/06 §3).
    var name: String {
        switch self {
        case .onbStepViewed: "onb_step_viewed"
        case .onbStepCompleted: "onb_step_completed"
        case .onbAnchorCaptured: "onb_anchor_captured"
        case .onbPayoffShown: "onb_payoff_shown"
        case .searchPerformed: "search_performed"
        case .itemLogged: "item_logged"
        case .chipApplied: "chip_applied"
        case .fitCaptured: "fit_captured"
        case .faceoffCompleted: "faceoff_completed"
        case .faceoffSkipped: "faceoff_skipped"
        case .shelfViewed: "shelf_viewed"
        case .productViewed: "product_viewed"
        case .leaderboardViewed: "leaderboard_viewed"
        case .importCompleted: "import_completed"
        case .shareInReceived: "share_in_received"
        case .cutoutCaptured: "cutout_captured"
        case .exportGenerated: "export_generated"
        case .recImpression: "rec_impression"
        case .recTapped: "rec_tapped"
        case .recDismissed: "rec_dismissed"
        case .errorShown: "error_shown"
        case .restrictedActionBlocked: "restricted_action_blocked"
        }
    }

    /// Props as they go over the wire. Ids render as UUID strings, enums as
    /// their raw values; nils are omitted rather than sent as nulls.
    var props: [String: PropValue] {
        switch self {
        case let .onbStepViewed(step, branch), let .onbStepCompleted(step, branch):
            ["step": .string(step), "branch": .optional(branch?.rawValue)].compacted()
        case let .onbAnchorCaptured(brandID, variantID, fit):
            ["brand_id": .id(brandID), "variant_id": .id(variantID), "fit": .string(fit)]
        case let .onbPayoffShown(exactShadeCount, evidenceBacked):
            ["n_exact_shade": .int(exactShadeCount), "evidence_backed": .bool(evidenceBacked)]
        case let .searchPerformed(queryHash, domain, hit, resultCount, source):
            [
                "query_hash": .string(queryHash),
                "domain": .optional(domain),
                "hit": .bool(hit),
                "result_count": .int(resultCount),
                "source": .string(source.rawValue)
            ].compacted()
        case let .itemLogged(variantID, categoryID, source, scope):
            [
                "variant_id": .id(variantID),
                "category_id": .id(categoryID),
                "source": .string(source.rawValue),
                "scope": .string(scope)
            ]
        case let .chipApplied(chipID, kind, week):
            ["chip_id": .id(chipID), "kind": .string(kind), "week": .optionalInt(week)].compacted()
        case let .fitCaptured(fits):
            // The whole multi-axis answer (GLO-67): sorted so identical
            // captures compare equal in rollups.
            ["fits": .string(fits.sorted().joined(separator: ","))]
        case let .faceoffCompleted(categoryID, sessionLength), let .faceoffSkipped(categoryID, sessionLength):
            ["category_id": .id(categoryID), "session_len": .int(sessionLength)]
        case .shelfViewed:
            [:]
        case let .productViewed(productID):
            ["product_id": .id(productID)]
        case let .leaderboardViewed(categoryID, scope):
            ["category_id": .id(categoryID), "scope": .string(scope)]
        case let .importCompleted(source, lines, matched, toLadder):
            [
                "source": .string(source),
                "lines": .int(lines),
                "matched": .int(matched),
                "to_ladder": .int(toLadder)
            ]
        case let .shareInReceived(sourceHost, resolved):
            ["source_host": .string(sourceHost), "resolved": .bool(resolved)]
        case let .cutoutCaptured(confidenceBand, retake):
            ["confidence_band": .string(confidenceBand), "retake": .bool(retake)]
        case let .exportGenerated(itemCount):
            ["item_count": .int(itemCount)]
        case let .recImpression(slot, variantID), let .recTapped(slot, variantID):
            ["slot": .string(slot.rawValue), "variant_id": .id(variantID)]
        case let .recDismissed(slot, variantID, reason):
            [
                "slot": .string(slot.rawValue),
                "variant_id": .id(variantID),
                "reason": .optional(reason)
            ].compacted()
        case let .errorShown(code, supportReference):
            ["code": .string(code), "support_ref": .string(supportReference)]
        case let .restrictedActionBlocked(surface, action):
            ["surface": .string(surface), "action": .string(action)]
        }
    }
}

/// The only shapes a prop can take. There is deliberately no free-form
/// dictionary or array — a prop that does not fit these is a prop the
/// registry should not carry.
public enum PropValue: Sendable, Equatable {
    case id(UUID)
    case string(String)
    case int(Int)
    case bool(Bool)
    case absent

    static func optional(_ value: String?) -> PropValue {
        value.map(PropValue.string) ?? .absent
    }

    static func optionalInt(_ value: Int?) -> PropValue {
        value.map(PropValue.int) ?? .absent
    }

    /// The JSON fragment this renders as.
    var jsonValue: Any? {
        switch self {
        case let .id(uuid): uuid.uuidString.lowercased()
        case let .string(string): string
        case let .int(int): int
        case let .bool(bool): bool
        case .absent: nil
        }
    }
}

extension [String: PropValue] {
    /// Absent values are omitted, not sent as nulls.
    func compacted() -> [String: PropValue] {
        filter { $0.value != .absent }
    }
}

public extension Event {
    /// A stable, salted hash for search queries: analytics can count and
    /// distinguish queries without holding their text — the raw query already
    /// has its one home in `failed_searches`.
    ///
    /// FNV-1a over the salted, normalized query. Not cryptographic and not
    /// meant to be: the property that matters is that the same query hashes
    /// the same within an install and nothing readable rides in props.
    static func queryHash(_ query: String, salt: UUID) -> String {
        let input = salt.uuidString + query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
