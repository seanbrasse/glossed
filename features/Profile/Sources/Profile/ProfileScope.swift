import DataKit
import Foundation

// The tab strip's vocabulary: which tabs exist, and what each one's scope mark
// says (GLO-261). The grids' own contents and seams are next door in
// `ProfileTabsStores.swift`; both were one file until it crossed SwiftLint's
// 300-line ceiling — the same remedy `RoutinesModels.swift` applied to
// `RoutinesRepository.swift`.

/// What the profile shows under the identity block: your looks, your
/// collections, your routines, your shelf (GLO-261).
///
/// **`looks` is first and is the default**, which is Sean's instruction —
/// "users will see their bio, pfp, name, and then looks as default". The
/// frame's two-segment `Segmented ['routines','collections']` is superseded.
///
/// The set is still derived from the seams the app actually filled, so a tab
/// never appears in front of a surface that cannot answer: a tab whose content
/// is "coming soon" is the drawer's `collections land with GLO-21` mistake
/// wearing different words (GLO-189).
public enum ProfileTab: String, CaseIterable, Sendable {
    case looks, collections, routines, shelf

    /// Lowercase, like every label in the app.
    public var label: String {
        rawValue
    }

    /// Which account-level privacy surface governs this tab, when one does.
    ///
    /// **`collections` returns nil, and that is a fact about the schema rather
    /// than an omission here.** `visibility_surface` has four members — shelf,
    /// rankings, routines, looks — and collections is not one of them:
    /// `collections.visibility` is a per-row `scope_enum` column, so a
    /// collection carries its own scope and the account carries none for them.
    /// `ProfileScopeMark.ceiling` is what closes that gap.
    public var surface: VisibilitySurface? {
        switch self {
        case .looks: .looks
        case .collections: nil
        case .routines: .routines
        case .shelf: .shelf
        }
    }
}

/// What a tab's scope mark says: the most any other person could reach in this
/// tab.
///
/// **The mark is a ceiling, deliberately.** A privacy signal that understates
/// is the one that hurts, so a tab holding five private collections and one
/// public one is marked `public` — something in here is reachable. A mark that
/// averaged, or reported the strictest, would tell you nothing was published
/// while something was.
///
/// This is the whole of what earns the right to delete `StrangerPreviewView`
/// (GLO-190, reversed by GLO-261). Your own profile shows your private things
/// because you cannot manage what you cannot see; the mark on the tab is what
/// makes "and a stranger sees only some of this" visible on the screen itself
/// instead of behind a modal you have to remember to open.
public enum ProfileScopeMark: Sendable, Equatable {
    case onlyYou, friends, publicToAnyone

    /// `PrivacyScope`'s own words, which are the app's words — "only you",
    /// never "just you" (Sean, Aug 29).
    public var label: String {
        switch self {
        case .onlyYou: PrivacyScope.onlyYou.label
        case .friends: PrivacyScope.friends.label
        case .publicToAnyone: PrivacyScope.publicScope.label
        }
    }

    /// Read out in full to VoiceOver, where a two-word label beside a tab name
    /// would be read as part of the tab name.
    public var spokenLabel: String {
        switch self {
        case .onlyYou: "visible to only you"
        case .friends: "visible to friends"
        case .publicToAnyone: "visible to anyone"
        }
    }

    public init(_ scope: PrivacyScope) {
        switch scope {
        case .onlyYou: self = .onlyYou
        case .friends: self = .friends
        case .publicScope: self = .publicToAnyone
        }
    }

    /// The loosest of a set of scopes, or `only you` when the set is empty —
    /// which is the `scope_enum` column default and so the true answer for a
    /// tab holding nothing.
    public static func ceiling(of scopes: [PrivacyScope]) -> ProfileScopeMark {
        if scopes.contains(.publicScope) {
            return .publicToAnyone
        }
        return scopes.contains(.friends) ? .friends : .onlyYou
    }
}

/// The signed-in user's four account-level scopes, for the tab marks.
///
/// **Not `PublicProfile.shelfVisible` and friends, which is what this looks
/// like it should be.** Those three are the VIEWER's permission, computed by
/// `can_view` server-side — and `can_view` short-circuits to true when viewer
/// = owner, so on your own profile all three read `true` at every scope. A
/// mark built on them would say `public` over an `only_you` shelf, which is
/// precisely the failure GLO-190 existed to catch. `privacy_scopes` is the
/// column, and `StrangerPreviewModel` read it for the same reason before this
/// screen absorbed the job.
public struct ProfileScopesStore: Sendable {
    public var scopes: @Sendable () async throws -> PrivacyScopes

    public init(scopes: @escaping @Sendable () async throws -> PrivacyScopes) {
        self.scopes = scopes
    }

    public static func live(_ privacy: PrivacyRepository) -> ProfileScopesStore {
        ProfileScopesStore(scopes: { try await privacy.scopes() })
    }
}
