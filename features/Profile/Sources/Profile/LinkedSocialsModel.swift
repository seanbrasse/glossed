import DataKit
import Foundation

public struct LinkedSocialsStore: Sendable {
    public var load: @Sendable () async throws -> [PublicText]
    public var save: @Sendable (String) async throws -> Void

    public init(
        load: @escaping @Sendable () async throws -> [PublicText],
        save: @escaping @Sendable (String) async throws -> Void
    ) {
        self.load = load
        self.save = save
    }

    public static func live(_ repository: SafetyRepository) -> LinkedSocialsStore {
        LinkedSocialsStore(
            load: { try await repository.myPublicTexts() },
            save: { try await repository.submitPublicText(kind: .linkedSocial, body: $0) }
        )
    }
}

@MainActor
@Observable
public final class LinkedSocialsModel {
    public var typed: String = ""
    public private(set) var saved: PublicText?
    public private(set) var isLoading = true
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    private let store: LinkedSocialsStore

    public init(store: LinkedSocialsStore) {
        self.store = store
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            saved = try await store.load().first { $0.kind == .linkedSocial }
            typed = saved?.body ?? ""
        } catch {
            errorMessage = (error as? GlossedError)?.userMessage ?? "couldn't load that."
        }
    }

    public var canSave: Bool {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != saved?.body && !isSaving
    }

    public func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let body = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            try await store.save(body)
            await load()
        } catch {
            errorMessage = (error as? GlossedError)?.userMessage ?? "that didn't save. try again."
        }
    }

    /// Nothing renders a linked social to anyone (GLO-189): no RPC returns
    /// one, and `public_profile` has no field for it. So the state cannot be
    /// described in terms of review — "not yet reviewed" implies review is the
    /// only thing in the way, and it is not.
    public var stateLine: String {
        guard saved != nil else { return "" }
        return "saved to your account. nothing shows it to anyone yet — that part isn't built."
    }

    public var isPending: Bool {
        saved?.state == .pending
    }
}
