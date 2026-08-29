import DataKit
import Foundation

/// How the privacy screen reaches persistence. A struct of closures rather than
/// the repository itself, so the model is testable without a live client —
/// same shape as `ProductFitStore`.
public struct PrivacyStore: Sendable {
    public var load: @Sendable () async throws -> PrivacyScopes
    public var setScope: @Sendable (VisibilitySurface, PrivacyScope) async throws -> Void
    public var setDiscoverable: @Sendable (Bool) async throws -> Void

    public init(
        load: @escaping @Sendable () async throws -> PrivacyScopes,
        setScope: @escaping @Sendable (VisibilitySurface, PrivacyScope) async throws -> Void,
        setDiscoverable: @escaping @Sendable (Bool) async throws -> Void
    ) {
        self.load = load
        self.setScope = setScope
        self.setDiscoverable = setDiscoverable
    }

    public static func live(_ repository: PrivacyRepository) -> PrivacyStore {
        PrivacyStore(
            load: { try await repository.scopes() },
            setScope: { try await repository.setScope($0, to: $1) },
            setDiscoverable: { try await repository.setDiscoverable($0) }
        )
    }
}

/// The four rows the screen shows, in the order it shows them.
///
/// `looks` is deliberately absent: the column exists so Phase 2 inherits a
/// tested one, but there are no looks to scope yet and a row governing nothing
/// is a promise the app cannot keep. It joins the list when looks ship.
public enum PrivacyRow: CaseIterable, Sendable {
    case shelf, rankings, routines

    public var surface: VisibilitySurface {
        switch self {
        case .shelf: .shelf
        case .rankings: .rankings
        case .routines: .routines
        }
    }

    public var title: String {
        switch self {
        case .shelf: "your shelf"
        case .rankings: "your rankings"
        case .routines: "your routines"
        }
    }

    /// What is actually exposed, in the user's terms. Vague copy on a privacy
    /// screen is a way of not answering the question.
    public var detail: String {
        switch self {
        case .shelf: "the products you've logged, and what you think of them."
        case .rankings: "your ordered lists, and where each product sits."
        case .routines: "your am, pm, weekly and wash-day steps."
        }
    }
}

/// The privacy screen's state.
///
/// Every scope change writes immediately — there is no save button. A privacy
/// screen with unsaved state is a screen that can lie about what is exposed,
/// and the failure mode of forgetting to tap save is the one that matters.
@MainActor
@Observable
public final class PrivacyModel {
    public private(set) var scopes = PrivacyScopes()
    public private(set) var isLoading = true
    /// Set when a write fails. The row reverts, because showing the new value
    /// after a failed write is the screen lying about what is exposed.
    public private(set) var errorMessage: String?
    /// A minor's scope write is refused by the database. The screen locks
    /// rather than letting them tap into a refusal repeatedly.
    public private(set) var isLockedByAgeGate = false

    private let store: PrivacyStore

    public init(store: PrivacyStore) {
        self.store = store
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            scopes = try await store.load()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func setScope(_ row: PrivacyRow, to scope: PrivacyScope) async {
        let previous = scopes
        scopes = Self.applying(scope, to: row, in: scopes)
        errorMessage = nil
        do {
            try await store.setScope(row.surface, scope)
        } catch {
            // Revert. An optimistic update that survives a failed write leaves
            // the screen claiming a shelf is private when the database still
            // says public — the one lie this screen must never tell.
            scopes = previous
            noteFailure(error)
        }
    }

    public func setDiscoverable(_ on: Bool) async {
        let previous = scopes
        scopes = Self.applying(discoverable: on, in: scopes)
        errorMessage = nil
        do {
            try await store.setDiscoverable(on)
        } catch {
            scopes = previous
            noteFailure(error)
        }
    }

    private func noteFailure(_ error: Error) {
        if let glossed = error as? GlossedError, glossed.code == .underAgeMinimum {
            isLockedByAgeGate = true
        }
        errorMessage = Self.message(for: error)
    }

    static func message(for error: Error) -> String {
        (error as? GlossedError)?.userMessage ?? "that didn't save. try again."
    }

    static func applying(_ scope: PrivacyScope, to row: PrivacyRow, in current: PrivacyScopes) -> PrivacyScopes {
        PrivacyScopes(
            shelf: row == .shelf ? scope : current.shelf,
            rankings: row == .rankings ? scope : current.rankings,
            routines: row == .routines ? scope : current.routines,
            looks: current.looks,
            discoverable: current.discoverable
        )
    }

    static func applying(discoverable: Bool, in current: PrivacyScopes) -> PrivacyScopes {
        PrivacyScopes(
            shelf: current.shelf,
            rankings: current.rankings,
            routines: current.routines,
            looks: current.looks,
            discoverable: discoverable
        )
    }

    /// The line above the rows. `nil` from `overallScope` means the rows
    /// disagree, and the screen says so rather than rounding — rounding to the
    /// loosest shows "public" to someone whose rankings are private, and to the
    /// tightest hides that something is public.
    public var summaryLine: String {
        guard let overall = scopes.overallScope else { return "mixed" }
        return overall.label
    }

    /// Discoverable is not a scope, and the screen has to say why it is a
    /// separate switch: a public shelf someone can open by link is not the same
    /// as being offered to strangers.
    public var discoverableDetail: String {
        "let people find you in suggestions and browse. your scopes above still decide what they can see."
    }
}
