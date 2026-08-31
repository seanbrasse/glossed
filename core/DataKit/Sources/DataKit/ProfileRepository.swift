import Foundation
import Supabase

/// The signed-in user's own `profiles` row — the onboarding prior half of
/// the profile principle (GLO-162: onboarding is the prior, logged
/// experience is the evidence, evidence wins).
///
/// Opened by Sean's per-session grant, Aug 29, for GLO-18: until this,
/// nothing in DataKit could create a profile row at all, which is GLO-182's
/// root — `is_minor_user` coalesces a missing row to true (deliberately),
/// so every account was a minor until onboarding could write.
///
/// Reads and writes are RLS-scoped to the caller (`profiles_own`, all
/// commands); `requireUserID()` fails fast rather than issuing a query that
/// would silently return nothing.
public struct ProfileRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    /// The caller's row, or nil — and nil is a STATE, not an error: no row
    /// means the server treats them as a minor (0020's default-deny), and
    /// callers branch on that rather than on a thrown absence.
    public func own() async throws(GlossedError) -> Profile? {
        _ = try await client.requireUserID()
        let rows: [Profile] = try await run {
            try await client.supabase
                .from("profiles")
                .select()
                .execute()
                .value
        }
        return rows.first
    }

    /// Stores the pfp's R2 key after a successful upload (GLO-272 — the
    /// avatar's edit icon). The KEY, not a URL: the app composes read URLs
    /// through `storage_presign`'s own-pfp read, and the column is Regulated
    /// the moment it holds a face (domain.md §5) — never into logs, props or
    /// breadcrumbs; this method never even prints it. RLS pins the write to
    /// the caller's own row; `updated_at` ships by hand (profiles carries no
    /// touch trigger, `rename`'s rule elsewhere).
    public func setPhotoKey(_ key: String) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("profiles")
                .update(PhotoKeyUpdate(photoR2Key: key, updatedAt: Date().ISO8601Format()))
                .eq("user_id", value: userID.uuidString)
                .execute()
        }
    }

    /// One write, exactly its columns — the StateUpdate discipline.
    struct PhotoKeyUpdate: Encodable, Sendable {
        let photoR2Key: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case photoR2Key = "photo_r2_key"
            case updatedAt = "updated_at"
        }
    }

    /// The caller's shade anchor, or nil — and nil is a STATE the tune
    /// card exists for. The anchor is DERIVED (`user_shade_anchor` is a view
    /// over logged anchor-category items joined to their fits), so there is
    /// no anchor write here or anywhere: logging + capturing fit IS setting
    /// the anchor, through the shelf paths that already exist. Newest wins,
    /// the leaderboard RPC's own rule.
    public func anchor() async throws(GlossedError) -> ShadeAnchorFact? {
        _ = try await client.requireUserID()
        let rows: [ShadeAnchorFact] = try await run {
            try await client.supabase
                .from("user_shade_anchor")
                .select()
                .order("captured_at", ascending: false)
                .limit(1)
                .execute()
                .value
        }
        return rows.first
    }

    /// Writes the onboarding prior in one idempotent upsert. Validates
    /// client-side first so a bad value fails as `invalid_input` with words,
    /// not as a check-constraint string from Postgres.
    public func saveProfile(_ draft: ProfileDraft) async throws(GlossedError) {
        if let invalid = ProfileDraft.firstInvalidField(draft) {
            throw GlossedError(
                .invalidInput,
                userMessage: "that \(invalid) doesn't look right — try again.",
                debugDetail: "profile draft failed validation: \(invalid)"
            )
        }
        let userID = try await client.requireUserID()
        let row = draft.row(userID: userID)
        try await run {
            _ = try await client.supabase
                .from("profiles")
                .upsert(row, onConflict: "user_id")
                .execute()
        }
    }

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}

/// One row of the derived anchor view — the caller's own, via RLS on the
/// tables underneath.
public struct ShadeAnchorFact: Codable, Sendable, Equatable {
    public let variantID: UUID
    public let fit: Fit
    public let capturedAt: Date?

    enum CodingKeys: String, CodingKey {
        case variantID = "variant_id"
        case fit
        case capturedAt = "captured_at"
    }
}

/// The row as the app reads it back.
public struct Profile: Codable, Sendable, Equatable {
    public let userID: UUID
    public let displayName: String?
    public let birthYearMonth: String
    public let domains: [Domain]
    public let skinType: SkinType?
    public let concerns: [String]
    public let toneBand: Int?
    public let hairPattern: String?
    public let climate: String?
    public let brandAffinities: [String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case birthYearMonth = "birth_year_month"
        case domains, concerns, climate
        case skinType = "skin_type"
        case toneBand = "tone_band"
        case hairPattern = "hair_pattern"
        case brandAffinities = "brand_affinities"
    }
}

/// The database's own vocabulary for skin type — the check constraint's
/// four values, no more.
public enum SkinType: String, Codable, Sendable, CaseIterable {
    case oily, dry, combo, sensitive
}

/// What onboarding knows by the time the account exists. Everything after
/// the birthday is optional — the quiz's whole design is that skin type,
/// concerns and brands come after you're in.
public struct ProfileDraft: Sendable, Equatable {
    /// "2001-07" — the wire shape the DB's check constraint demands.
    /// Birthday, not age range (PRD §17); the server derives minor status.
    public var birthYearMonth: String
    public var domains: [Domain]
    public var skinType: SkinType?
    /// 1–10 on the tone scale, matching the DB check.
    public var toneBand: Int?
    /// "3b" — 1–4 then a–c, matching the DB check.
    public var hairPattern: String?
    public var concerns: [String]
    public var climate: String?
    public var displayName: String?
    /// Nil means "not asked", and the column is left untouched — the tune
    /// screen is the only asker, so onboarding's write can never erase a
    /// later answer (the never-erase design, now explicit in the type).
    public var brandAffinities: [String]?

    public init(
        birthYearMonth: String,
        domains: [Domain],
        skinType: SkinType? = nil,
        toneBand: Int? = nil,
        hairPattern: String? = nil,
        concerns: [String] = [],
        climate: String? = nil,
        displayName: String? = nil,
        brandAffinities: [String]? = nil
    ) {
        self.birthYearMonth = birthYearMonth
        self.domains = domains
        self.skinType = skinType
        self.toneBand = toneBand
        self.hairPattern = hairPattern
        self.concerns = concerns
        self.climate = climate
        self.displayName = displayName
        self.brandAffinities = brandAffinities
    }

    /// "2001-07" from parts, or nil for a month no calendar has — the
    /// feature builds this from the native wheel, so nil means a bug there,
    /// not user error.
    public static func birthYearMonth(year: Int, month: Int) -> String? {
        guard (1 ... 12).contains(month), (1000 ... 9999).contains(year) else { return nil }
        return String(format: "%04d-%02d", year, month)
    }

    /// The DB's checks, applied before the network: the name of the first
    /// field that would bounce, or nil when the row will land.
    public static func firstInvalidField(_ draft: ProfileDraft) -> String? {
        if draft.birthYearMonth.wholeMatch(of: /\d{4}-(0[1-9]|1[0-2])/) == nil {
            return "birthday"
        }
        if draft.domains.isEmpty {
            // the quiz's own invariant: at least one domain, always
            return "domains"
        }
        if let tone = draft.toneBand, !(1 ... 10).contains(tone) {
            return "tone band"
        }
        if let hair = draft.hairPattern, hair.wholeMatch(of: /[1-4][a-c]/) == nil {
            return "hair type"
        }
        return nil
    }

    func row(userID: UUID) -> ProfileRow {
        ProfileRow(
            userID: userID.uuidString,
            displayName: displayName,
            birthYearMonth: birthYearMonth,
            domains: domains.map(\.rawValue),
            skinType: skinType?.rawValue,
            concerns: concerns,
            toneBand: toneBand,
            hairPattern: hairPattern,
            climate: climate,
            brandAffinities: brandAffinities
        )
    }
}

/// The wire row. `brand_affinities` encodes ONLY when the draft carries an
/// answer (synthesized Encodable omits nil keys): onboarding never asks, so
/// its upserts leave the column untouched; the tune screen asks, so its
/// saves carry it — the never-erase design, held by the encoder.
struct ProfileRow: Encodable {
    let userID: String
    let displayName: String?
    let birthYearMonth: String
    let domains: [String]
    let skinType: String?
    let concerns: [String]
    let toneBand: Int?
    let hairPattern: String?
    let climate: String?
    let brandAffinities: [String]?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case birthYearMonth = "birth_year_month"
        case domains, concerns, climate
        case skinType = "skin_type"
        case toneBand = "tone_band"
        case hairPattern = "hair_pattern"
        case brandAffinities = "brand_affinities"
    }
}
