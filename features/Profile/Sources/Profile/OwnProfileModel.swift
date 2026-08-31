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

    /// Sean's metrics, one mono line under the identity block (GLO-261):
    ///
    /// > "you'll see metrics like your followers, your following, maybe
    /// > profile views, amount of things on your shelf."
    ///
    /// Three of the four. **Profile views does not exist** — no table, no
    /// counter, no write path — and Sean's "maybe" is doing real work: it
    /// needs a retention rule, a decision about whether the viewed person
    /// learns who viewed them, and a write on a read path. GLO-262 carries
    /// that cost. Nothing here stands in for it.
    ///
    /// **`ranked lists` leaves the line**, which `G.Profile` and the merged
    /// build both carried. Sean named three counts and this is his screen; the
    /// ranked-list count is still on `PublicProfile` and still true, it is
    /// just not one of the three he asked to see.
    ///
    /// Every part is a count of YOUR OWN things, not a claim about people, so
    /// none of it takes an `EvidenceLine` — that primitive is for a claim with
    /// a cohort behind it, and borrowing its chrome here would dress three
    /// counts up as evidence. There is no cohort, and there are no stars.
    ///
    /// Zero is shown, not hidden: a count that disappears when it is
    /// unflattering is not a count.
    public var statLine: String {
        [
            Self.count(followersN, "follower", "followers"),
            "\(followingN) following",
            "\(profile?.shelfN ?? 0) on your shelf"
        ].joined(separator: " · ")
    }

    /// The identity block's first line: your display name, or your handle when
    /// you have not set one, or the pre-claim state.
    ///
    /// Sean's sketch puts the name above the handle. A profile with no display
    /// name promotes the handle rather than leading with a blank line — the
    /// handle is still the address (GLO-187), so it is never absent from the
    /// block, only sometimes second.
    public var leadName: String {
        displayName ?? handle.map { "@\($0)" } ?? "no handle yet"
    }

    /// The line under the name — the handle, and only when the name is not
    /// already it. Nil rather than a repeat: a profile that printed `@maya_k`
    /// twice would read as two facts about one.
    public var handleLine: String? {
        guard let handle, displayName != nil else { return nil }
        return "@\(handle)"
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
