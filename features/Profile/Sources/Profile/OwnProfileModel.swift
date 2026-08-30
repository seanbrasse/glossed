import DataKit
import Foundation

/// How the own-profile screen reaches persistence.
public struct OwnProfileStore: Sendable {
    public var handle: @Sendable () async throws -> String?
    public var profile: @Sendable (String) async throws -> PublicProfile?
    public var badges: @Sendable () async throws -> ProfileBadges
    public var setBadge: @Sendable (ProfileBadges.Badge, Bool) async throws -> Void

    public init(
        handle: @escaping @Sendable () async throws -> String?,
        profile: @escaping @Sendable (String) async throws -> PublicProfile?,
        badges: @escaping @Sendable () async throws -> ProfileBadges,
        setBadge: @escaping @Sendable (ProfileBadges.Badge, Bool) async throws -> Void
    ) {
        self.handle = handle
        self.profile = profile
        self.badges = badges
        self.setBadge = setBadge
    }

    public static func live(social: SocialRepository, safety: SafetyRepository) -> OwnProfileStore {
        OwnProfileStore(
            handle: { try await social.myHandle() },
            profile: { try await social.publicProfile(handle: $0) },
            badges: { try await safety.badges() },
            setBadge: { try await safety.setBadge($0, on: $1) }
        )
    }
}

/// The own-profile screen's state.
@MainActor
@Observable
public final class OwnProfileModel {
    public private(set) var handle: String?
    public private(set) var profile: PublicProfile?
    public private(set) var badges = ProfileBadges()
    public private(set) var isLoading = true
    public private(set) var errorMessage: String?

    private let store: OwnProfileStore

    public init(store: OwnProfileStore) {
        self.store = store
    }

    /// No handle is not an error — it is the pre-claim state, and the screen
    /// says so with a way forward rather than an empty page.
    public var needsHandle: Bool {
        handle == nil
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            handle = try await store.handle()
            badges = try await store.badges()
            if let handle {
                profile = try await store.profile(handle)
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func setBadge(_ badge: ProfileBadges.Badge, on: Bool) async {
        let previous = badges
        badges = Self.applying(badge, on: on, to: badges)
        errorMessage = nil
        do {
            try await store.setBadge(badge, on)
        } catch {
            // Revert. A badge switch that stays on after a failed write tells
            // the user they are publishing something they are not — or worse,
            // that they are not publishing something they are.
            badges = previous
            errorMessage = Self.message(for: error)
        }
    }

    nonisolated static func applying(
        _ badge: ProfileBadges.Badge,
        on: Bool,
        to current: ProfileBadges
    ) -> ProfileBadges {
        ProfileBadges(
            showSkinType: badge == .skinType ? on : current.showSkinType,
            showAnchor: badge == .anchor ? on : current.showAnchor,
            showHairPattern: badge == .hairPattern ? on : current.showHairPattern
        )
    }

    nonisolated static func message(for error: Error) -> String {
        (error as? GlossedError)?.userMessage ?? "that didn't save. try again."
    }

    /// The frame's one mono stat line, which the built screen had split into
    /// three count cells and an `EvidenceLine`.
    ///
    /// `G.Profile` writes `34 shelved · 7 ranked lists · 1 product you
    /// created`. The third clause is dropped: `public_profile` returns no
    /// created-product count, and printing the fixture's `1` would be the
    /// profile describing someone else. Follows are appended instead — the
    /// frame predates handles and following entirely, and delta 11 shipped
    /// both, so the line carries the facts this build actually has in the
    /// shape the frame draws them.
    ///
    /// Every part is a count of YOUR OWN things, not a claim about people, so
    /// none of it takes an `EvidenceLine` — that primitive is for a claim with
    /// a cohort behind it, and borrowing its chrome here would dress four
    /// counts up as evidence.
    ///
    /// Zero is shown, not hidden: a count that disappears when it is
    /// unflattering is not a count.
    public var statLine: String {
        [
            Self.count(profile?.shelfN ?? 0, "shelved", "shelved"),
            Self.count(rankedListsN, "ranked list", "ranked lists"),
            Self.count(followersN, "follower", "followers"),
            "\(followingN) following"
        ].joined(separator: " · ")
    }

    nonisolated static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    public var followersN: Int {
        profile?.followers ?? 0
    }

    public var followingN: Int {
        profile?.following ?? 0
    }

    public var rankedListsN: Int {
        profile?.rankedListsN ?? 0
    }

    /// What the avatar draws its initial from — the same source every other
    /// screen uses.
    ///
    /// `ViewedProfileView` and `StrangerPreviewView` both pass
    /// `displayName ?? handle`; this screen passed `handle` alone. That was
    /// harmless until #352 made a display name settable, and then it wasn't:
    /// set the name "rae" on the handle `@maya_k` and everyone else sees "r"
    /// while your own profile shows "m". You would be the only person looking
    /// at a different avatar than the one you have.
    ///
    /// It lives on the model rather than in the view so the rule is one
    /// expression a test can hold, instead of three call sites that have
    /// already drifted once.
    public var avatarName: String {
        profile?.displayName ?? handle ?? "?"
    }

    /// The name and the bio as they are PUBLISHED, which is not the same as
    /// the ones you typed.
    ///
    /// Both come from `public_profile`, so the bio is the `approved` body from
    /// `public_texts` (`tech/02` §3.2) and a pending edit reads as the previous
    /// text or as nothing. That is the point rather than a rounding error: this
    /// screen is where you find out what is actually visible, and showing the
    /// draft here would tell you a review had finished when it had not. The
    /// settings row is the other half — it shows what you typed, with the
    /// row's own `state` read back beside it (#363).
    public var displayName: String? {
        profile?.displayName
    }

    public var bio: String? {
        profile?.bio
    }

    /// True when the handle exists but the PROFILE is not reachable — which is
    /// not a moderation state. The handle itself is public the moment it is
    /// claimed (GLO-187); this covers the profile read failing for another
    /// reason, and says nothing about review.
    public var profileUnreachable: Bool {
        handle != nil && profile == nil
    }
}
