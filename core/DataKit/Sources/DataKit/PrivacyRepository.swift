import Foundation
import Supabase

/// Who can see each of your surfaces. Migration 0020, `docs/tech/02` §1.
///
/// The label is **"only you"**, never "just you" (Sean, Aug 29). The kit's
/// privacy frame still shows the old string and is superseded, not a spec.
public enum PrivacyScope: String, Codable, Sendable, CaseIterable {
    case onlyYou = "only_you"
    case friends
    case publicScope = "public"

    /// Lowercase UI copy, per the kit's voice. `public` is a Swift keyword, so
    /// the case is spelled differently from its wire value — this is the only
    /// place that difference should ever be visible.
    public var label: String {
        switch self {
        case .onlyYou: "only you"
        case .friends: "friends"
        case .publicScope: "public"
        }
    }

    /// What the scope actually means, for the row's supporting line. "friends"
    /// is mutual follow (Sean, Aug 29) — a stranger cannot self-serve into a
    /// friends-scoped surface by tapping follow.
    public var explanation: String {
        switch self {
        case .onlyYou: "nobody else can see this."
        case .friends: "people you follow who follow you back."
        case .publicScope: "anyone, including people who aren't signed in."
        }
    }
}

/// The four surfaces a scope applies to. Mirrors `visibility_surface`.
/// `looks` is inert until Phase 2 and ships now so Phase 2 inherits a tested
/// column rather than a migration.
public enum VisibilitySurface: String, Codable, Sendable, CaseIterable {
    case shelf, rankings, routines, looks
}

/// One row of `privacy_scopes`.
///
/// `discoverable` is deliberately NOT a scope. Being visible and wanting to be
/// *surfaced* are different questions (§1.3): a public shelf you can reach by
/// link is not the same as appearing in someone's suggestions. Browse and
/// suggested-people both require it; `can_view` never consults it.
public struct PrivacyScopes: Codable, Sendable, Equatable {
    public let shelf: PrivacyScope
    public let rankings: PrivacyScope
    public let routines: PrivacyScope
    public let looks: PrivacyScope
    public let discoverable: Bool

    enum CodingKeys: String, CodingKey {
        case shelf, rankings, routines, looks, discoverable
    }

    public init(
        shelf: PrivacyScope = .onlyYou,
        rankings: PrivacyScope = .onlyYou,
        routines: PrivacyScope = .onlyYou,
        looks: PrivacyScope = .onlyYou,
        discoverable: Bool = false
    ) {
        self.shelf = shelf
        self.rankings = rankings
        self.routines = routines
        self.looks = looks
        self.discoverable = discoverable
    }

    public func scope(for surface: VisibilitySurface) -> PrivacyScope {
        switch surface {
        case .shelf: shelf
        case .rankings: rankings
        case .routines: routines
        case .looks: looks
        }
    }

    /// The summary the privacy screen shows above the four rows — GLO-119
    /// calls this the "derived master"; the name here avoids a term the lint
    /// config rejects, and the behaviour is the ticket's.
    ///
    /// READ-ONLY and derived, never stored: a single stored summary would let
    /// it and the rows disagree, and the rows are the truth.
    ///
    /// `nil` means the four rows are mixed — which the screen states plainly
    /// rather than rounding to the loosest or the tightest.
    public var overallScope: PrivacyScope? {
        let all = [shelf, rankings, routines, looks]
        return all.allSatisfy { $0 == shelf } ? shelf : nil
    }
}

/// Reads and writes the signed-in user's privacy scopes, and asks the one
/// visibility question the client is allowed to ask.
///
/// Everything here is scoped to the caller by RLS (`privacy_scopes_own`), so
/// there is no user parameter anywhere — a repository that took one would be
/// offering a question the database will not answer.
public struct PrivacyRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    /// The caller's scopes. A user with no row yet gets the all-private
    /// default rather than an error: **no row is not a missing answer, it is
    /// `only_you`** — the same rule `can_view` applies server-side. Returning
    /// nil here would invite a screen to render "unknown" for a state that is
    /// definitively private.
    public func scopes() async throws(GlossedError) -> PrivacyScopes {
        let userID = try await client.requireUserID()
        let rows: [PrivacyScopes] = try await run {
            try await client.supabase
                .from("privacy_scopes")
                .select("shelf,rankings,routines,looks,discoverable")
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
        }
        return rows.first ?? PrivacyScopes()
    }

    /// Sets one surface. Upsert rather than update: the row may not exist yet,
    /// and a first-time change to one surface must not require the screen to
    /// have created a row first.
    ///
    /// A minor's write is refused by the database (`privacy_scopes_minor_lock`),
    /// not by this method. The check is deliberately not mirrored here — a
    /// client-side age test is a second source of truth that can drift from the
    /// one that matters, and the trigger is the one that cannot be bypassed.
    public func setScope(_ surface: VisibilitySurface, to scope: PrivacyScope) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("privacy_scopes")
                .upsert(
                    [
                        "user_id": userID.uuidString,
                        surface.rawValue: scope.rawValue
                    ],
                    onConflict: "user_id"
                )
                .execute()
        }
    }

    /// Opts in or out of being surfaced in suggestions and browse. Separate
    /// call from `setScope` because it is a separate decision (§1.3).
    public func setDiscoverable(_ discoverable: Bool) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("privacy_scopes")
                .upsert(
                    ["user_id": userID.uuidString, "discoverable": String(discoverable)],
                    onConflict: "user_id"
                )
                .execute()
        }
    }

    /// May the CALLER see this owner's surface?
    ///
    /// The two-argument `can_view` — the only arity clients can reach. The
    /// three-argument core takes an arbitrary viewer and stays server-side, so
    /// a client cannot probe visibility between two other people.
    ///
    /// Blocked, minor, and no-such-user all answer `false`, identically and on
    /// purpose: "not found" and "blocked" must be indistinguishable (§1.5).
    public func canView(owner: UUID, surface: VisibilitySurface) async throws(GlossedError) -> Bool {
        try await run {
            try await client.supabase
                .rpc("can_view", params: ["p_owner": owner.uuidString, "p_surface": surface.rawValue])
                .execute()
                .value
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
