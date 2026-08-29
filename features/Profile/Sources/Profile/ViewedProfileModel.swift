import DataKit
import Foundation

/// How the viewed-profile screen reaches persistence.
public struct ViewedProfileStore: Sendable {
    public var profile: @Sendable (String) async throws -> PublicProfile?
    public var isFollowing: @Sendable (UUID) async throws -> Bool
    public var canFollow: @Sendable (UUID) async throws -> Bool
    public var follow: @Sendable (UUID) async throws -> Void
    public var unfollow: @Sendable (UUID) async throws -> Void
    public var suggestions: @Sendable (Int) async throws -> [SuggestedPerson]

    public init(
        profile: @escaping @Sendable (String) async throws -> PublicProfile?,
        isFollowing: @escaping @Sendable (UUID) async throws -> Bool,
        canFollow: @escaping @Sendable (UUID) async throws -> Bool,
        follow: @escaping @Sendable (UUID) async throws -> Void,
        unfollow: @escaping @Sendable (UUID) async throws -> Void,
        suggestions: @escaping @Sendable (Int) async throws -> [SuggestedPerson]
    ) {
        self.profile = profile
        self.isFollowing = isFollowing
        self.canFollow = canFollow
        self.follow = follow
        self.unfollow = unfollow
        self.suggestions = suggestions
    }

    public static func live(_ repository: SocialRepository) -> ViewedProfileStore {
        ViewedProfileStore(
            profile: { try await repository.publicProfile(handle: $0) },
            isFollowing: { try await repository.isFollowing($0) },
            canFollow: { try await repository.canFollow($0) },
            follow: { try await repository.follow($0) },
            unfollow: { try await repository.unfollow($0) },
            suggestions: { try await repository.suggestedPeople(limit: $0) }
        )
    }
}

/// What the follow control offers.
public enum FollowState: Equatable, Sendable {
    case following
    case notFollowing
    /// The caller may not follow: a minor, or a block in either direction. The
    /// control is absent rather than disabled — a greyed button invites the
    /// question "why not", and the honest answer is one we must not give.
    case unavailable
}

/// Someone else's profile.
///
/// **A missing profile is one state, not four.** No such handle, a minor owner,
/// a block in either direction, or otherwise unreachable all arrive as nil from
/// `public_profile`, and this model keeps them indistinguishable. §1.5 is
/// explicit: "not found" and "blocked" are the same response. A screen that
/// said "this person has blocked you" would leak exactly what the block exists
/// to prevent.
@MainActor
@Observable
public final class ViewedProfileModel {
    public private(set) var profile: PublicProfile?
    public private(set) var followState: FollowState = .unavailable
    public private(set) var isLoading = true
    public private(set) var errorMessage: String?

    private let store: ViewedProfileStore
    private let handle: String
    /// The follow graph keys on user id, and `public_profile` does not return
    /// one — deliberately, since a handle→id mapping would make the graph
    /// enumerable. The caller supplies the id it already holds (a suggestion
    /// row carries one); without it the profile still renders, minus the
    /// follow control.
    private let userID: UUID?

    public init(store: ViewedProfileStore, handle: String, userID: UUID? = nil) {
        self.store = store
        self.handle = handle
        self.userID = userID
    }

    /// True when there is nothing to show. The copy must not speculate.
    public var isUnavailable: Bool {
        !isLoading && profile == nil
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await store.profile(handle)
            guard profile != nil, let userID else {
                followState = .unavailable
                return
            }
            if try await store.isFollowing(userID) {
                followState = .following
            } else {
                followState = try await store.canFollow(userID) ? .notFollowing : .unavailable
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Follows or unfollows, whichever the current state implies.
    ///
    /// No pre-flight `canFollow`: the insert policy enforces the same rule, so
    /// checking first would be a second source of truth plus a race. The state
    /// reverts if the write fails.
    public func toggleFollow() async {
        guard let userID, followState != .unavailable else { return }
        let previous = followState
        followState = previous == .following ? .notFollowing : .following
        errorMessage = nil
        do {
            if previous == .following {
                try await store.unfollow(userID)
            } else {
                try await store.follow(userID)
            }
        } catch {
            followState = previous
            errorMessage = Self.message(for: error)
        }
    }

    nonisolated static func message(for error: Error) -> String {
        (error as? GlossedError)?.userMessage ?? "that didn't work. try again."
    }

    /// The surfaces this viewer may actually open, with the ones they may not
    /// stated plainly rather than hidden.
    ///
    /// Hiding a locked surface would leave the viewer wondering whether it
    /// exists; saying "private" is true, says nothing about the viewer, and is
    /// the same answer whether the scope is `only_you` or `friends`.
    public var surfaces: [(label: String, visible: Bool)] {
        guard let profile else { return [] }
        return [
            ("shelf", profile.shelfVisible),
            ("rankings", profile.rankingsVisible),
            ("routines", profile.routinesVisible)
        ]
    }
}

/// The suggested-people card.
///
/// One person with a named reason, never a three-avatar grid — the design rule
/// and the evidence rule meeting on the same card.
@MainActor
@Observable
public final class SuggestedPeopleModel {
    public private(set) var people: [SuggestedPerson] = []
    public private(set) var isLoading = true

    private let store: ViewedProfileStore

    public init(store: ViewedProfileStore) {
        self.store = store
    }

    /// Empty is the CORRECT state, not a failure.
    ///
    /// Reasons are gated on `profile_badges`, which default false (Sean,
    /// Aug 29), so this returns nothing until people opt in. The card says so
    /// rather than spinning or showing a skeleton that never fills.
    public var isEmptyForGoodReason: Bool {
        !isLoading && people.isEmpty
    }

    public func load(limit: Int = 5) async {
        isLoading = true
        defer { isLoading = false }
        people = await (try? store.suggestions(limit)) ?? []
    }

    public var emptyLine: String {
        "no suggestions yet. people show up here once they've chosen to share what they wear."
    }
}
