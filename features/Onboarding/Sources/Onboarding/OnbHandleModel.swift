import DataKit
import Foundation
import Observation

/// How the handle step reaches persistence. A closure seam, not a repository,
/// for the reason every other seam in this package is one: features never
/// import features, and the model is driven in tests with no client present.
public struct OnbHandleStore: Sendable {
    public var isAvailable: @Sendable (String) async throws -> Bool
    public var claim: @Sendable (String) async throws -> String

    public init(
        isAvailable: @escaping @Sendable (String) async throws -> Bool,
        claim: @escaping @Sendable (String) async throws -> String
    ) {
        self.isAvailable = isAvailable
        self.claim = claim
    }
}

/// What the field can say about what is typed.
public enum OnbHandleVerdict: Equatable, Sendable {
    case empty
    /// Fails the shape rule. Checked on device so the field can answer while
    /// typing — this is input formatting, not authorization, and the server
    /// still decides. `claim_handle` carries the checks that matter: the minor
    /// gate, the reserved list, and the brand-name collision that makes
    /// impersonation harder as the catalog grows.
    case malformed
    case checking
    case taken
    case available
    /// The check itself failed. Distinct from `taken` on purpose: "we could
    /// not ask" is not "somebody has it", and telling a user their handle is
    /// taken when the network dropped is a lie that costs them a name.
    case failed(String)
}

@MainActor
@Observable
public final class OnbHandleModel {
    public private(set) var typed = ""
    public private(set) var verdict = OnbHandleVerdict.empty
    public private(set) var isClaiming = false

    private let store: OnbHandleStore?
    /// The name collected one screen earlier, for the suggestion.
    private let suggestedFrom: String
    var checkTask: Task<Void, Never>?
    var claimTask: Task<Void, Never>?

    public init(store: OnbHandleStore? = nil, suggestedFrom: String = "") {
        self.store = store
        self.suggestedFrom = suggestedFrom
    }

    /// A handle is an identifier (GLO-191), so the rule is the identifier's:
    /// lowercase letters, digits, dot, underscore. Everything else is dropped
    /// rather than rejected — a name with a space in it should become a
    /// suggestion, not an error.
    public static func normalize(_ raw: String) -> String {
        String(raw.lowercased().compactMap { character in
            if character.isLetter || character.isNumber {
                return character
            }
            if character == "." || character == "_" {
                return character
            }
            if character == " " || character == "-" {
                return "_"
            }
            return nil
        }.prefix(30))
    }

    /// Pre-fills from the name, and **only pre-fills**. Asked whether to
    /// auto-assign a handle, the answer is no: an assigned one means
    /// collisions resolved into `maya_k_4821`, which is an identity nobody
    /// chose on the one field the product calls "how people find you". This
    /// costs a tap to accept and nothing to ignore.
    public func suggest() {
        guard typed.isEmpty else { return }
        let seed = Self.normalize(suggestedFrom)
        guard !seed.isEmpty else { return }
        typing(seed)
    }

    public func typing(_ raw: String) {
        typed = Self.normalize(raw)
        checkTask?.cancel()
        guard !typed.isEmpty else {
            verdict = .empty
            return
        }
        guard typed.count >= 2 else {
            verdict = .malformed
            return
        }
        guard let store else {
            verdict = .available
            return
        }
        verdict = .checking
        let candidate = typed
        checkTask = Task {
            do {
                let free = try await store.isAvailable(candidate)
                guard !Task.isCancelled, candidate == typed else { return }
                verdict = free ? .available : .taken
            } catch {
                guard !Task.isCancelled, candidate == typed else { return }
                verdict = .failed(
                    (error as? GlossedError)?.userMessage ?? "couldn't check that one. try again."
                )
            }
        }
    }

    public var canClaim: Bool {
        verdict == .available
    }

    /// The claim is the server's, and a refusal here is final for this
    /// attempt: `claim_handle` runs every check in one transaction, so a
    /// handle that returns IS live. Failure keeps the screen — there is no
    /// path past this step without one.
    public func claim(onClaimed: @escaping () -> Void) {
        guard canClaim, !isClaiming else { return }
        guard let store else {
            onClaimed()
            return
        }
        isClaiming = true
        let candidate = typed
        claimTask = Task {
            defer { isClaiming = false }
            do {
                _ = try await store.claim(candidate)
                onClaimed()
            } catch {
                guard !Task.isCancelled else { return }
                verdict = .failed(
                    (error as? GlossedError)?.userMessage ?? "couldn't claim that one. try another."
                )
            }
        }
    }
}
