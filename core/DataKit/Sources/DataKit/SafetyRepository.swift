import Foundation
import Supabase

/// Blocking, muting, reporting, and the two publication surfaces that carry
/// Regulated data — badges and public text.
///
/// Grouped together because they share one property: each is a decision about
/// what other people can see or do, and every one of them is enforced by the
/// database rather than by whether a screen offered the control.
public struct SafetyRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    // MARK: - Blocking

    /// Blocks someone. The follow edges in BOTH directions are severed by a
    /// trigger, not by this call — a block that leaves a follow standing is a
    /// bug that reads as a working feature.
    public func block(_ target: UUID) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("blocks")
                .insert(["user_id": userID.uuidString, "blocked_id": target.uuidString])
                .execute()
        }
    }

    public func unblock(_ target: UUID) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("blocks")
                .delete()
                .eq("user_id", value: userID.uuidString)
                .eq("blocked_id", value: target.uuidString)
                .execute()
        }
    }

    /// Who the caller has blocked, for the blocked-list screen.
    ///
    /// Only the blocker's own rows — `blocks` RLS is deliberately
    /// blocker-only, so there is no way to ask "who has blocked me" and no
    /// method here that pretends there is. The blocked party must not be able
    /// to detect the block from data.
    public func blockedList() async throws(GlossedError) -> [UUID] {
        let userID = try await client.requireUserID()
        let rows: [BlockRow] = try await run {
            try await client.supabase
                .from("blocks")
                .select("blocked_id")
                .eq("user_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
        return rows.map(\.blockedID)
    }

    // MARK: - Muting

    /// Mutes someone: they stop appearing in your suggestions and browse rows.
    ///
    /// Changes no visibility in either direction — that is the whole difference
    /// from a block, and the confirm copy has to say it, because a user who
    /// expects mute to hide them from the other person has been misled.
    public func mute(_ target: UUID) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("mutes")
                .insert(["user_id": userID.uuidString, "muted_id": target.uuidString])
                .execute()
        }
    }

    public func unmute(_ target: UUID) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("mutes")
                .delete()
                .eq("user_id", value: userID.uuidString)
                .eq("muted_id", value: target.uuidString)
                .execute()
        }
    }

    // MARK: - Reporting

    /// Files a report. Reports outlive the content they describe (T&S, two
    /// years) and survive account deletion with the personal fields gone, which
    /// is why the table's user references are `on delete set null` rather than
    /// cascade.
    ///
    /// Nothing is auto-actioned from here. `underage` and `self_harm` route to
    /// a same-day human per `docs/runbook.md` §1 — and that runbook is
    /// currently NOT OPERATIVE (no named owner, Sean parked moderation on
    /// Aug 29), so a report filed today is stored and not worked. The report
    /// sheet must not promise a response it cannot keep.
    public func report(
        subject: ReportSubject,
        subjectID: UUID?,
        subjectUserID: UUID?,
        reason: ReportReason,
        detail: String? = nil
    ) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        var row: [String: String?] = [
            "reporter_id": userID.uuidString,
            "subject_kind": subject.rawValue,
            "reason": reason.rawValue
        ]
        row["subject_id"] = subjectID?.uuidString
        row["subject_user_id"] = subjectUserID?.uuidString
        row["detail"] = detail
        try await run {
            _ = try await client.supabase.from("reports").insert(row).execute()
        }
    }

    // MARK: - Badges

    public func badges() async throws(GlossedError) -> ProfileBadges {
        let userID = try await client.requireUserID()
        let rows: [ProfileBadges] = try await run {
            try await client.supabase
                .from("profile_badges")
                .select("show_skin_type,show_anchor,show_hair_pattern")
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
        }
        // No row means nothing is published, which is the same as all-false.
        // Defaulting here rather than returning nil keeps "hasn't decided" and
        // "decided not to" indistinguishable — they have identical consequences
        // and a screen should not invent a difference.
        return rows.first ?? ProfileBadges()
    }

    /// Turns one badge on or off. Upsert because the row may not exist yet.
    ///
    /// A minor's badge write is refused by the database. Not mirrored here, for
    /// the same reason the privacy screen does not mirror the minor lock: a
    /// client-side age test is a second source of truth free to drift.
    public func setBadge(_ badge: ProfileBadges.Badge, on: Bool) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("profile_badges")
                .upsert(
                    ["user_id": userID.uuidString, badge.rawValue: String(on)],
                    onConflict: "user_id"
                )
                .execute()
        }
    }

    // MARK: - Public text

    /// Submits user-authored text for review. Always lands `pending`.
    ///
    /// **Pending renders nothing to anyone else** (§3.2), so this is safe to
    /// call the moment the user finishes typing — the window between the write
    /// and the model's answer is exactly where a naive design leaks, and the
    /// render rule closes it.
    ///
    /// With moderation parked (Sean, Aug 29) nothing moves rows out of
    /// `pending`, so text submitted today stays invisible to others
    /// indefinitely. That is the correct failure — unmoderated text is not
    /// published — but the screen must say "waiting to be reviewed" rather
    /// than implying it is live.
    public func submitPublicText(
        kind: PublicTextKind,
        subjectID: UUID? = nil,
        body: String
    ) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        var row: [String: String?] = [
            "user_id": userID.uuidString,
            "kind": kind.rawValue,
            "body": body,
            "state": ModerationState.pending.rawValue
        ]
        row["subject_id"] = subjectID?.uuidString
        try await run {
            _ = try await client.supabase
                .from("public_texts")
                .upsert(row, onConflict: "user_id,kind,subject_id")
                .execute()
        }
    }

    /// The caller's own public texts, including pending ones — this is the
    /// author's view, which is the only place unapproved text may render.
    public func myPublicTexts() async throws(GlossedError) -> [PublicText] {
        let userID = try await client.requireUserID()
        return try await run {
            try await client.supabase
                .from("public_texts")
                .select("kind,subject_id,body,state")
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
        }
    }

    private struct BlockRow: Decodable {
        let blockedID: UUID

        enum CodingKeys: String, CodingKey {
            case blockedID = "blocked_id"
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
