import DataKit
import Foundation

/// How the settings screen reaches persistence. GLO-213.
public struct SettingsStore: Sendable {
    public var profile: @Sendable () async throws -> Profile?
    public var anchor: @Sendable () async throws -> ShadeAnchorFact?
    public var signOut: @Sendable () async throws -> Void
    /// Read-modify-write, and it has to be: `saveProfile` upserts the WHOLE
    /// row. Anything this draft omits with a default is written as that
    /// default — `concerns` is non-optional and defaults to `[]`, so a partial
    /// draft erases the user's skin concerns (GLO-215). Every field is carried
    /// across from the current profile deliberately.
    public var saveDisplayName: @Sendable (String) async throws -> Void

    public init(
        profile: @escaping @Sendable () async throws -> Profile?,
        anchor: @escaping @Sendable () async throws -> ShadeAnchorFact?,
        signOut: @escaping @Sendable () async throws -> Void,
        saveDisplayName: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.profile = profile
        self.anchor = anchor
        self.signOut = signOut
        self.saveDisplayName = saveDisplayName
    }

    public static func live(_ repository: ProfileRepository, client: GlossedClient) -> SettingsStore {
        SettingsStore(
            profile: { try await repository.own() },
            anchor: { try await repository.anchor() },
            signOut: { try await client.signOut() },
            saveDisplayName: { name in
                guard let current = try await repository.own() else {
                    throw GlossedError(
                        .notFound,
                        userMessage: "finish signing up first — then a name has somewhere to save."
                    )
                }
                try await repository.saveProfile(ProfileDraft(
                    birthYearMonth: current.birthYearMonth,
                    domains: current.domains,
                    skinType: current.skinType,
                    toneBand: current.toneBand,
                    hairPattern: current.hairPattern,
                    // Carried, not defaulted. See saveDisplayName's note.
                    concerns: current.concerns,
                    climate: current.climate,
                    displayName: name,
                    // nil means "not asked" — the only field with that
                    // contract, and this screen does not ask about brands.
                    brandAffinities: nil
                ))
            }
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
    /// Kept so the name editor can open prefilled without a second read.
    public private(set) var displayName: String?
    public private(set) var isLoading = true
    public private(set) var errorMessage: String?
    /// Internal so the name editor can reach its save without the model
    /// re-declaring every store function it does not otherwise use.
    let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let profile = try? await store.profile()
        let anchor = try? await store.anchor()
        displayName = (profile ?? nil)?.displayName
        rows = Self.rows(profile: profile ?? nil, anchor: anchor ?? nil)
    }

    /// Sign-out failure is stated rather than swallowed. A tap that appears to
    /// do nothing on the row that ends your session is worse than an error —
    /// the next thing the user does is assume they are signed out.
    /// Re-reads after the name changes so the row shows what was saved rather
    /// than what was typed — the two differ if the write is trimmed or refused.
    public func reload() async {
        await load()
    }

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
            SettingsRow(id: "name", label: "your name", value: profile?.displayName),
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
