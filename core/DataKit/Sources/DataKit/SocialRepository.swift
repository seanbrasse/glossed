import Foundation
import Supabase

/// A public profile as another person sees it. Mirrors `public_profile`'s
/// return, which is a PROJECTION — `profiles` RLS never relaxes (§2.2), so
/// nothing here is a row anyone could have selected.
///
/// Badges are nil unless the owner opted in AND is not a minor. A nil badge
/// means "not published", never "not known" — the RPC does not distinguish
/// them for the caller, on purpose.
public struct PublicProfile: Codable, Sendable, Equatable {
    public let handle: String
    public let displayName: String?
    public let avatarSeed: String?
    public let bio: String?
    public let badgeSkinType: String?
    public let badgeAnchor: String?
    public let badgeHairPattern: String?
    /// The n behind every claim the profile makes. No count renders without
    /// one, and no surface renders a claim it cannot count.
    public let followers: Int
    public let following: Int
    public let shelfN: Int
    public let rankedListsN: Int
    /// Whether the VIEWER may open each surface — computed by `can_view`
    /// server-side, so the client never re-derives visibility.
    public let shelfVisible: Bool
    public let rankingsVisible: Bool
    public let routinesVisible: Bool

    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
        case avatarSeed = "avatar_seed"
        case bio
        case badgeSkinType = "badge_skin_type"
        case badgeAnchor = "badge_anchor"
        case badgeHairPattern = "badge_hair_pattern"
        case followers, following
        case shelfN = "shelf_n"
        case rankedListsN = "ranked_lists_n"
        case shelfVisible = "shelf_visible"
        case rankingsVisible = "rankings_visible"
        case routinesVisible = "routines_visible"
    }
}

/// Why someone is being suggested. The card's whole contract: one person with
/// a NAMED reason, never a three-avatar grid.
public struct SuggestedPerson: Codable, Sendable, Equatable, Identifiable {
    public let userID: UUID
    public let handle: String
    public let displayName: String?
    /// Never empty — the RPC returns no row rather than a reasonless one, so
    /// there is no "blank card" state for a view to handle.
    public let reason: String
    public let reasonKind: String
    /// The n the reason carries: how many things this person ranks.
    public let n: Int

    public var id: UUID {
        userID
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case handle
        case displayName = "display_name"
        case reason
        case reasonKind = "reason_kind"
        case n
    }
}

/// Handles, public profiles, and the follow graph.
///
/// The graph is deliberately not selectable: `follows` RLS shows you only your
/// own edges, and follower counts come from `public_profile`'s definer RPC.
/// That is what keeps the graph unscrapable one profile at a time, and it is
/// why there is no `followers(of:)` method here to reach for.
public struct SocialRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    // MARK: - Handles

    /// Is this handle free? Cheap enough to call as the user types.
    ///
    /// A `true` here is NOT a reservation — `claim_handle` is the only thing
    /// that decides, and it can still refuse a handle this said was free. The
    /// screen must treat this as a hint and the claim as the answer.
    public func handleAvailable(_ handle: String) async throws(GlossedError) -> Bool {
        try await run {
            try await client.supabase
                .rpc("handle_available", params: ["p_handle": handle])
                .execute()
                .value
        }
    }

    /// Claims a handle for the signed-in user, returning the handle as stored.
    ///
    /// The returned value can differ from what was passed — the database
    /// normalizes — so the screen must render what comes back rather than what
    /// the user typed. Reserved words, impersonation-risk names, taken handles
    /// and minors are all refused server-side; the errors arrive as
    /// `GlossedError` with the database's own message behind them.
    public func claimHandle(_ handle: String) async throws(GlossedError) -> String {
        _ = try await client.requireUserID()
        return try await run {
            try await client.supabase
                .rpc("claim_handle", params: ["p_handle": handle])
                .execute()
                .value
        }
    }

    /// The caller's own handle, or nil if they have not claimed one.
    ///
    /// Reads `handles` under `handles_read_own`, which shows a user exactly one
    /// row: theirs. There is no method here for looking up someone else's
    /// handle by id — the public direction is `publicProfile(handle:)`, and a
    /// reverse lookup would turn a user id into a public identity, which is a
    /// different thing to expose.
    ///
    /// Not in GLO-171's enumeration; the own-profile screen it serves is one of
    /// the screens that opening was granted for, so it lands under the same
    /// grant rather than a new one.
    public func myHandle() async throws(GlossedError) -> String? {
        let userID = try await client.requireUserID()
        let rows: [HandleRow] = try await run {
            try await client.supabase
                .from("handles")
                .select("handle")
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
        }
        return rows.first?.handle
    }

    // MARK: - Public profiles

    /// Someone's public profile, or nil.
    ///
    /// **Nil covers four different situations on purpose**: no such handle, the
    /// owner is a minor, a block exists in either direction, or the profile is
    /// otherwise unreachable. The RPC returns zero rows for all of them and the
    /// client must not try to tell them apart — "not found" and "blocked" being
    /// indistinguishable is the point (§1.5), and a screen that said "this user
    /// has blocked you" would leak exactly what the block is for.
    public func publicProfile(handle: String) async throws(GlossedError) -> PublicProfile? {
        let rows: [PublicProfile] = try await run {
            try await client.supabase
                .rpc("public_profile", params: ["p_handle": handle])
                .execute()
                .value
        }
        return rows.first
    }

    // MARK: - Following

    /// May the caller follow this person? Answers only about `auth.uid()` —
    /// the client cannot ask about an arbitrary pair.
    ///
    /// False for a minor and for a blocked pair, identically. The caller learns
    /// nothing it could not learn by trying, which is why the wrapper is safe
    /// to expose at all.
    public func canFollow(_ target: UUID) async throws(GlossedError) -> Bool {
        _ = try await client.requireUserID()
        return try await run {
            try await client.supabase
                .rpc("can_follow", params: ["p_target": target.uuidString])
                .execute()
                .value
        }
    }

    /// Follows someone. One-directional and needs no approval; `friends` scope
    /// requires both edges (Sean, Aug 29), so following alone grants nothing.
    ///
    /// No pre-flight `canFollow` call: the insert policy enforces the same
    /// rule, and checking first would be a second source of truth plus a race.
    /// `canFollow` exists for the button's ENABLED state, not as a gate.
    public func follow(_ target: UUID) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("follows")
                .insert(["follower_id": userID.uuidString, "followed_id": target.uuidString])
                .execute()
        }
    }

    /// Unfollows. Either party may remove the edge, so this also serves
    /// "remove a follower" without escalating to a block.
    public func unfollow(_ target: UUID) async throws(GlossedError) {
        let userID = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("follows")
                .delete()
                .eq("follower_id", value: userID.uuidString)
                .eq("followed_id", value: target.uuidString)
                .execute()
        }
    }

    /// Is the caller following this person? Reads the caller's own edge, which
    /// is the only part of the graph RLS will show them.
    public func isFollowing(_ target: UUID) async throws(GlossedError) -> Bool {
        let userID = try await client.requireUserID()
        let rows: [FollowEdge] = try await run {
            try await client.supabase
                .from("follows")
                .select("follower_id,followed_id")
                .eq("follower_id", value: userID.uuidString)
                .eq("followed_id", value: target.uuidString)
                .execute()
                .value
        }
        return !rows.isEmpty
    }

    // MARK: - Suggestions

    /// People to follow, each with a named reason carrying its n.
    ///
    /// Returns empty until people opt into badges — reasons are gated on
    /// `profile_badges`, which default false (Sean, Aug 29). **An empty list is
    /// the correct state, not an error and not a loading failure**, and the
    /// screen has to say so rather than spinning.
    public func suggestedPeople(limit: Int = 10) async throws(GlossedError) -> [SuggestedPerson] {
        _ = try await client.requireUserID()
        return try await run {
            try await client.supabase
                .rpc("suggested_people", params: ["p_limit": String(limit)])
                .execute()
                .value
        }
    }

    private struct HandleRow: Decodable {
        let handle: String
    }

    private struct FollowEdge: Decodable {
        let followerID: UUID
        let followedID: UUID

        enum CodingKeys: String, CodingKey {
            case followerID = "follower_id"
            case followedID = "followed_id"
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
