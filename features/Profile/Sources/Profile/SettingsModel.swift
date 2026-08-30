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
    /// The bio editor's own store, carried here so settings can present it.
    /// Optional because a store built without one simply omits the row rather
    /// than showing a row that opens nothing.
    public var bio: BioStore?

    public init(
        profile: @escaping @Sendable () async throws -> Profile?,
        anchor: @escaping @Sendable () async throws -> ShadeAnchorFact?,
        signOut: @escaping @Sendable () async throws -> Void,
        saveDisplayName: @escaping @Sendable (String) async throws -> Void = { _ in },
        bio: BioStore? = nil
    ) {
        self.profile = profile
        self.anchor = anchor
        self.signOut = signOut
        self.saveDisplayName = saveDisplayName
        self.bio = bio
    }

    public static func live(
        _ repository: ProfileRepository, client: GlossedClient, safety: SafetyRepository
    ) -> SettingsStore {
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
            },
            bio: .live(safety: safety)
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
public struct SettingsRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let value: String?

    public init(id: String, label: String, value: String?) {
        self.id = id
        self.label = label
        self.value = value
    }

    /// Which rows open an editor. **Derived here rather than decided in the
    /// view**, so "the birthday is not editable" is one expression a test can
    /// hold instead of an `if` in a `@ViewBuilder` that a later refactor can
    /// quietly widen.
    ///
    /// The birthday is the one that matters (GLO-257). It is the **18+ gate** —
    /// the screen map's caption on the onboarding birthday step is *"18+ gate
    /// and recs only, never on the profile"* — and a gate the gated party can
    /// edit is not a gate. It also feeds `is_minor_user`, which every Phase-1.5
    /// surface depends on; GLO-182 is what a wrong answer looks like.
    ///
    /// It is rendered and **not offered**: no disabled field, no affordance,
    /// and no copy promising an appeal, because no appeal is built (GLO-189).
    /// If it needs to change, that is support's problem, not a text field.
    ///
    /// Every other row is either editable here or stated here and set
    /// elsewhere — onboarding, the tune sheet, the shelf.
    public var isEditable: Bool {
        id == "name" || id == "bio"
    }
}

/// One tap-into group on the settings root (GLO-257).
///
/// **A deliberate divergence from `G.Profile`, on Sean's direct instruction:**
/// *"We need better organization of settings… categories the user clicks into,
/// so settings looks less busy at first glance."* The frame draws a single
/// bordered card of seven flat rows. Recorded here so a later conformance
/// audit reads this before "fixing" it back.
public struct SettingsCategory: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let rows: [SettingsRow]

    public init(id: String, label: String, rows: [SettingsRow]) {
        self.id = id
        self.label = label
        self.rows = rows
    }

    /// What the root card says under the category name — the labels it holds,
    /// in order, in mono.
    ///
    /// This is the affordance as well as the preview: a category you can see
    /// into is one you only open when you want it, which is the whole of what
    /// Sean asked for. It is also why there is no chevron — the kit ships
    /// `ICONS.chevronRight` and DesignSystem has not ported it yet, and
    /// reaching for `Image(systemName:)` is GLO-64 exactly.
    public var summary: String {
        rows.map(\.label).joined(separator: " · ")
    }
}

@MainActor
@Observable
public final class SettingsModel {
    public private(set) var rows: [SettingsRow] = []
    public private(set) var categories: [SettingsCategory] = []
    /// Kept so the name editor can open prefilled without a second read.
    public private(set) var displayName: String?
    /// What the bio row shows. Read from `public_texts`, not the profile row —
    /// a bio is moderated text and lives apart from the quiz answers.
    public private(set) var bioBody: String?
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
        var bio: PublicText?
        if let bioStore = store.bio {
            bio = try? await bioStore.load()
        }
        displayName = (profile ?? nil)?.displayName
        bioBody = bio?.body
        rows = Self.rows(
            profile: profile ?? nil, anchor: anchor ?? nil,
            bio: store.bio == nil ? nil : (bio?.body ?? "")
        )
        categories = Self.categories(rows)
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
    ///
    /// `bio` is nil when this store has no bio editor at all, and the row is
    /// omitted rather than rendered dead. An empty string means the editor
    /// exists and nothing has been written yet, which the row states.
    static func rows(profile: Profile?, anchor: ShadeAnchorFact?, bio: String?) -> [SettingsRow] {
        [
            SettingsRow(id: "name", label: "your name", value: profile?.displayName),
            bio.map { SettingsRow(id: "bio", label: "your bio", value: $0.isEmpty ? nil : $0) },
            SettingsRow(id: "skin", label: "skin profile", value: skinLine(profile)),
            SettingsRow(id: "anchor", label: "shade anchor", value: anchorLine(anchor)),
            SettingsRow(id: "hair", label: "hair type", value: profile?.hairPattern),
            SettingsRow(id: "domains", label: "what you buy", value: domainLine(profile)),
            SettingsRow(id: "birthday", label: "birthday", value: birthdayLine(profile))
        ].compactMap(\.self)
    }

    /// The rows grouped into the two categories the root offers.
    ///
    /// Sean's examples were *personal details · user profile details ·
    /// privacy*. Checked against `docs/tech/02` §3 and PRD §09 before
    /// committing to it, and the split those two argue for is **what people
    /// see** versus **what the app knows**:
    ///
    /// - `your profile` is the published projection — §3.3's `public_profile`
    ///   returns exactly `display_name` and `bio` (plus badges, which are
    ///   published from the privacy screen, not here). These are the two rows
    ///   that change what a stranger reads.
    /// - `personal details` is everything the app knows and nobody sees. §3.4:
    ///   the body facts reach another person **only** as an opt-in badge, so
    ///   they are not profile fields, they are answers. PRD §09's two axes say
    ///   the same thing from the other side — contribution is always on and
    ///   invisible; visibility is the separate choice, and it is made under
    ///   `privacy`.
    ///
    /// Privacy is not a category here because it is already one screen
    /// (GLO-213 condensed it) owned by another feature, and it is opened
    /// rather than descended into.
    static func categories(_ rows: [SettingsRow]) -> [SettingsCategory] {
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        func group(_ id: String, _ label: String, _ ids: [String]) -> SettingsCategory? {
            let members = ids.compactMap { byID[$0] }
            return members.isEmpty ? nil : SettingsCategory(id: id, label: label, rows: members)
        }
        return [
            group("profile", "your profile", ["name", "bio"]),
            group("personal", "personal details", ["skin", "anchor", "hair", "domains", "birthday"])
        ].compactMap(\.self)
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
