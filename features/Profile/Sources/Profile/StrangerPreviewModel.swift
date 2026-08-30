import DataKit
import Foundation

/// Your profile as someone who is not signed in would see it.
///
/// Derived from your own settings, NOT from `public_profile` called on
/// yourself: `can_view` short-circuits when viewer = owner, so that call
/// returns `shelf_visible = true` even when the scope is `only_you`. A preview
/// built on it would claim a stranger sees a private shelf — the exact failure
/// this screen exists to catch.
public struct StrangerPreview: Sendable, Equatable {
    public let handle: String
    public let displayName: String?
    public let bio: String?
    public let skinType: String?
    public let anchor: String?
    public let hairPattern: String?
    public let shelfVisible: Bool
    public let rankingsVisible: Bool
    public let routinesVisible: Bool
    public let discoverable: Bool
    /// Surfaces a mutual follower would see that a stranger would not. Named
    /// rather than previewed: `friends` needs a real mutual follow to mean
    /// anything, and a fake one would be its own lie.
    public let friendsOnlySurfaces: [String]

    /// A stranger sees a surface only when its scope is `public`. `friends` is
    /// not a stranger — that distinction is the whole point of having three
    /// scopes rather than two.
    static func isPublic(_ scope: PrivacyScope) -> Bool {
        scope == .publicScope
    }

    public init(profile: PublicProfile, scopes: PrivacyScopes, badges: ProfileBadges) {
        handle = profile.handle
        displayName = profile.displayName
        bio = profile.bio
        skinType = badges.showSkinType ? profile.badgeSkinType : nil
        anchor = badges.showAnchor ? profile.badgeAnchor : nil
        hairPattern = badges.showHairPattern ? profile.badgeHairPattern : nil
        shelfVisible = Self.isPublic(scopes.shelf)
        rankingsVisible = Self.isPublic(scopes.rankings)
        routinesVisible = Self.isPublic(scopes.routines)
        discoverable = scopes.discoverable
        friendsOnlySurfaces = [
            (scopes.shelf, "shelf"), (scopes.rankings, "rankings"), (scopes.routines, "routines")
        ].filter { $0.0 == .friends }.map(\.1)
    }

    public var visibleSurfaces: [(label: String, visible: Bool)] {
        [("shelf", shelfVisible), ("rankings", rankingsVisible), ("routines", routinesVisible)]
    }

    public var nothingIsPublic: Bool {
        !shelfVisible && !rankingsVisible && !routinesVisible
            && skinType == nil && anchor == nil && hairPattern == nil && bio == nil
    }
}

public struct StrangerPreviewStore: Sendable {
    public var handle: @Sendable () async throws -> String?
    public var profile: @Sendable (String) async throws -> PublicProfile?
    public var scopes: @Sendable () async throws -> PrivacyScopes
    public var badges: @Sendable () async throws -> ProfileBadges

    public init(
        handle: @escaping @Sendable () async throws -> String?,
        profile: @escaping @Sendable (String) async throws -> PublicProfile?,
        scopes: @escaping @Sendable () async throws -> PrivacyScopes,
        badges: @escaping @Sendable () async throws -> ProfileBadges
    ) {
        self.handle = handle
        self.profile = profile
        self.scopes = scopes
        self.badges = badges
    }

    public static func live(
        social: SocialRepository, privacy: PrivacyRepository, safety: SafetyRepository
    ) -> StrangerPreviewStore {
        StrangerPreviewStore(
            handle: { try await social.myHandle() },
            profile: { try await social.publicProfile(handle: $0) },
            scopes: { try await privacy.scopes() },
            badges: { try await safety.badges() }
        )
    }
}

@MainActor
@Observable
public final class StrangerPreviewModel {
    public private(set) var preview: StrangerPreview?
    public private(set) var isLoading = true
    public private(set) var needsHandle = false

    private let store: StrangerPreviewStore

    public init(store: StrangerPreviewStore) {
        self.store = store
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let handle = try? await store.handle() else {
            needsHandle = true
            return
        }
        guard let profile = try? await store.profile(handle),
              let scopes = try? await store.scopes(),
              let badges = try? await store.badges()
        else { return }
        preview = StrangerPreview(profile: profile, scopes: scopes, badges: badges)
    }

    public var friendsLine: String? {
        guard let surfaces = preview?.friendsOnlySurfaces, !surfaces.isEmpty else { return nil }
        return "people you follow who follow you back also see your \(surfaces.joined(separator: ", "))."
    }
}
