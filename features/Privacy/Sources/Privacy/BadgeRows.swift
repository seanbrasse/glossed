import DataKit
import Foundation

/// How the privacy screen reaches the badge switches.
///
/// The badges moved here from `features/Profile` (GLO-213, Sean's ask to
/// condense "who can see your surfaces" and "what you show" into one privacy
/// menu). They belong here on the merits too: since GLO-205 these three
/// switches are the ONLY path by which a body fact reaches another person, so
/// a user checking their privacy should not have to know to look on a second
/// screen.
public struct BadgeStore: Sendable {
    public var badges: @Sendable () async throws -> ProfileBadges
    public var setBadge: @Sendable (ProfileBadges.Badge, Bool) async throws -> Void

    public init(
        badges: @escaping @Sendable () async throws -> ProfileBadges,
        setBadge: @escaping @Sendable (ProfileBadges.Badge, Bool) async throws -> Void
    ) {
        self.badges = badges
        self.setBadge = setBadge
    }

    public static func live(safety: SafetyRepository) -> BadgeStore {
        BadgeStore(
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
