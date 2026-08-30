import DataKit
import Foundation

/// How the bio editor reaches persistence. GLO-204.
public struct BioStore: Sendable {
    public var load: @Sendable () async throws -> PublicText?
    public var save: @Sendable (String) async throws -> Void

    public init(
        load: @escaping @Sendable () async throws -> PublicText?,
        save: @escaping @Sendable (String) async throws -> Void
    ) {
        self.load = load
        self.save = save
    }

    public static func live(safety: SafetyRepository) -> BioStore {
        BioStore(
            load: { try await safety.myPublicTexts().first { $0.kind == .bio } },
            // Through submitPublicText, which since GLO-216 calls the
            // set_public_text RPC. A direct table write is refused by RLS and
            // always was — that is what made linked socials tell people to
            // retry something impossible.
            save: { try await safety.submitPublicText(kind: .bio, body: $0) }
        )
    }
}

@MainActor
@Observable
public final class BioModel {
    public private(set) var saved: PublicText?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public var typed = ""
    private let store: BioStore

    public init(store: BioStore) {
        self.store = store
    }

    public func load() async {
        saved = try? await store.load()
        typed = saved?.body ?? ""
    }

    public var canSave: Bool {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != saved?.body && !isSaving
    }

    /// Re-reads after writing rather than assuming what landed.
    ///
    /// The server decides `state`, not this screen — `bios_auto_approve()`
    /// (GLO-207) is a switch someone flips before public launch. Reading the
    /// row back means the status line below is true in both positions instead
    /// of true until the day it is flipped.
    public func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            try await store.save(typed.trimmingCharacters(in: .whitespacesAndNewlines))
            saved = try? await store.load()
            typed = saved?.body ?? typed
        } catch {
            errorMessage = (error as? GlossedError)?.userMessage ?? "that didn't save. try again."
        }
    }

    /// What actually happened to the words, read from the row.
    ///
    /// Never "it's live" by assumption. A pending bio does not render on the
    /// profile at all — `public_profile` selects `state = 'approved'` — so
    /// saying it is visible when it is pending would be the GLO-189 shape,
    /// and saying it is under review when nothing reviews it would be the
    /// same lie pointing the other way.
    public var statusLine: String {
        guard let saved else { return "nothing saved yet." }
        switch saved.state {
        case .approved: return "live on your profile — anyone who can see it, sees this."
        case .pending: return "saved, and waiting to be looked at. it isn't on your profile yet."
        case .rejected: return "this wasn't approved, so it isn't on your profile."
        }
    }
}
