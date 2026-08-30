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

    /// What is actually visible, which is nothing until a review that is not
    /// happening. Moderation is parked, so this is the indefinite truth rather
    /// than a brief interstitial.
    public var stateLine: String {
        guard let saved else { return "" }
        switch saved.state {
        case .approved: return "visible on your profile."
        case .pending: return "saved. it won't show on your profile until it's been reviewed."
        case .rejected: return "this wasn't approved, so it isn't shown."
        }
    }

    public var isPending: Bool {
        saved?.state == .pending
    }
}
