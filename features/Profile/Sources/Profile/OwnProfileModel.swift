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

/// One badge row, with the copy that has to be right.
///
/// A badge publishes Regulated data (`domain.md` §5) by the user's own act, and
/// these three switches are **the only path** by which skin type, the anchor
/// shade and hair pattern reach another human (§3.4). So each row states what
/// it publishes and to whom, in plain words, before it is switched on — not
/// after, and not in a policy nobody opens.
public struct BadgeRow: Sendable, Identifiable {
    public let badge: ProfileBadges.Badge
    public let title: String
    public let detail: String

    public var id: String {
        badge.rawValue
    }

    public static let all: [BadgeRow] = [
        BadgeRow(
            badge: .skinType,
            title: "show your skin type",
            detail: """
            people whose skin type matches yours can see that it matches — \
            never what it is — and you can be suggested to them.
            """
        ),
        BadgeRow(
            badge: .anchor,
            title: "show the shade you wear",
            detail: "your anchor shade appears on your profile, and you can be suggested to people who wear it too."
        ),
        BadgeRow(
            badge: .hairPattern,
            title: "show your hair pattern",
            detail: "people whose hair pattern matches yours can see that it matches, never what it is."
        )
    ]
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

    /// The profile's own claim, carrying its n.
    ///
    /// A profile with an empty shelf says "0 things" rather than hiding the
    /// line: the count IS the claim, and a claim that disappears when it is
    /// unflattering is not evidence, it is marketing.
    public var shelfLine: String {
        let n = profile?.shelfN ?? 0
        return "\(n) \(n == 1 ? "thing" : "things") on your shelf"
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

    /// True when the handle exists but the PROFILE is not reachable — which is
    /// not a moderation state. The handle itself is public the moment it is
    /// claimed (GLO-187); this covers the profile read failing for another
    /// reason, and says nothing about review.
    public var profileUnreachable: Bool {
        handle != nil && profile == nil
    }
}
