import DataKit
import Foundation

/// How the settings screen reaches persistence. GLO-213.
public struct SettingsStore: Sendable {
    public var profile: @Sendable () async throws -> Profile?
    public var anchor: @Sendable () async throws -> ShadeAnchorFact?
    public var signOut: @Sendable () async throws -> Void

    public init(
        profile: @escaping @Sendable () async throws -> Profile?,
        anchor: @escaping @Sendable () async throws -> ShadeAnchorFact?,
        signOut: @escaping @Sendable () async throws -> Void
    ) {
        self.profile = profile
        self.anchor = anchor
        self.signOut = signOut
    }

    public static func live(_ repository: ProfileRepository, client: GlossedClient) -> SettingsStore {
        SettingsStore(
            profile: { try await repository.own() },
            anchor: { try await repository.anchor() },
            signOut: { try await client.signOut() }
        )
    }
}

/// One row in the settings card: a label, and what we can honestly say beside
/// it.
///
/// `value` is nil when the fact is genuinely unset, and the row renders "not
/// set yet" rather than borrowing the frame's example. The frame's fixture
/// reads "tone 6 · warm · combo"; a real account that never answered the quiz
/// has none of that, and printing the fixture would be a settings screen
/// describing someone else.
public struct SettingsRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: String?

    public init(id: String, label: String, value: String?) {
        self.id = id
        self.label = label
        self.value = value
    }
}

@MainActor
@Observable
public final class SettingsModel {
    public private(set) var rows: [SettingsRow] = []
    public private(set) var isLoading = true
    public private(set) var errorMessage: String?
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let profile = try? await store.profile()
        let anchor = try? await store.anchor()
        rows = Self.rows(profile: profile ?? nil, anchor: anchor ?? nil)
    }

    /// Sign-out failure is stated rather than swallowed. A tap that appears to
    /// do nothing on the row that ends your session is worse than an error —
    /// the next thing the user does is assume they are signed out.
    public func signOut() async -> Bool {
        errorMessage = nil
        do {
            try await store.signOut()
            return true
        } catch {
            errorMessage = "couldn't sign out — check your connection and try again."
            return false
        }
    }

    /// The frame's rows, minus the one we cannot fill.
    ///
    /// **`notifications` is deliberately absent.** The frame shows "rank nudges
    /// on"; there is no notification system, nothing to toggle, and nothing
    /// that would make the row true. A settings row for a feature that does
    /// not exist is a promise, and this project has shipped that mistake once
    /// already (GLO-189, copy promising a review nobody performs).
    static func rows(profile: Profile?, anchor: ShadeAnchorFact?) -> [SettingsRow] {
        [
            SettingsRow(id: "skin", label: "skin profile", value: skinLine(profile)),
            SettingsRow(id: "anchor", label: "shade anchor", value: anchorLine(anchor)),
            SettingsRow(id: "hair", label: "hair type", value: profile?.hairPattern),
            SettingsRow(id: "domains", label: "what you buy", value: domainLine(profile)),
            SettingsRow(id: "birthday", label: "birthday", value: birthdayLine(profile))
        ]
    }

    static func skinLine(_ profile: Profile?) -> String? {
        guard let profile else { return nil }
        let parts = [profile.toneBand.map { "tone \($0)" }, profile.skinType?.rawValue]
        let line = parts.compactMap(\.self).joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// The fit, not the shade. `user_shade_anchor` carries a variant id and a
    /// fit, not a brand or shade name — the frame's "fenty 240 · fit logged"
    /// would need a catalog lookup this screen does not do, and inventing the
    /// half we cannot read would be worse than naming the half we can.
    static func anchorLine(_ anchor: ShadeAnchorFact?) -> String? {
        anchor.map { "fit logged · \($0.fit.label)" }
    }

    static func domainLine(_ profile: Profile?) -> String? {
        guard let domains = profile?.domains, !domains.isEmpty else { return nil }
        return domains.map(\.rawValue).joined(separator: " · ")
    }

    /// Month and year, because that is all there is. The day is dropped before
    /// the write (`domain.md` §6) — the frame's "04 / 1998" shape implies a
    /// precision the database deliberately does not keep.
    static func birthdayLine(_ profile: Profile?) -> String? {
        guard let raw = profile?.birthYearMonth, raw.count == 7 else { return nil }
        let parts = raw.split(separator: "-")
        guard parts.count == 2 else { return nil }
        return "\(parts[1]) / \(parts[0])"
    }
}
