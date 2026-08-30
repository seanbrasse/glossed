import DataKit
import Foundation

/// How the handle screen reaches persistence.
public struct HandleStore: Sendable {
    public var isAvailable: @Sendable (String) async throws -> Bool
    public var claim: @Sendable (String) async throws -> String

    public init(
        isAvailable: @escaping @Sendable (String) async throws -> Bool,
        claim: @escaping @Sendable (String) async throws -> String
    ) {
        self.isAvailable = isAvailable
        self.claim = claim
    }

    public static func live(_ repository: SocialRepository) -> HandleStore {
        HandleStore(
            isAvailable: { try await repository.handleAvailable($0) },
            claim: { try await repository.claimHandle($0) }
        )
    }
}

/// What the field can say about what is typed.
public enum HandleVerdict: Equatable, Sendable {
    case empty
    /// Fails the shape rule. Checked on device only so the field can answer
    /// while typing — this is input formatting, not authorization, and the
    /// server still decides. Contrast the minor lock, which is deliberately
    /// NOT mirrored anywhere.
    case tooShort
    case badCharacters
    case checking
    case available
    /// Taken, reserved, or a brand name. **One verdict for three refusals on
    /// purpose**: `handle_available` returns a single boolean, and inventing a
    /// distinction the server did not make would either be a guess or require
    /// probing the reserved list, which is not a thing to hand a client.
    case unavailable

    public var isClaimable: Bool {
        self == .available
    }
}

/// The handle claim screen's state.
@MainActor
@Observable
public final class HandleClaimModel {
    /// What the user typed, normalized on the way in. The field shows the
    /// normalized form as they type, so what they see is what gets claimed —
    /// `claim_handle` lowercases and trims server-side, and a field that hid
    /// that would surprise someone who typed capitals.
    public var typed: String = "" {
        didSet {
            let normalized = Self.normalize(typed)
            if normalized != typed {
                typed = normalized
                return
            }
            verdict = Self.shapeVerdict(typed)
        }
    }

    public private(set) var verdict: HandleVerdict = .empty
    public private(set) var claimed: String?
    public private(set) var errorMessage: String?
    public private(set) var isClaiming = false

    private let store: HandleStore

    public init(store: HandleStore) {
        self.store = store
    }

    /// The shape rule, mirrored from the `handle_shape` check constraint:
    /// 2–30 chars, starting alphanumeric, then letters, digits, `_` or `.`,
    /// and no `..` run.
    nonisolated static func shapeVerdict(_ handle: String) -> HandleVerdict {
        if handle.isEmpty {
            return .empty
        }
        if handle.count < 2 {
            return .tooShort
        }
        if handle.count > 30 {
            return .badCharacters
        }
        if handle.contains("..") {
            return .badCharacters
        }
        guard let first = handle.first, first.isLetter || first.isNumber else { return .badCharacters }
        let allowed = handle.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" || $0 == "." }
        return allowed ? .checking : .badCharacters
    }

    /// Lowercase and strip whitespace. Everything else is left alone so the
    /// verdict can explain it rather than silently deleting what was typed —
    /// a field that eats characters teaches nothing.
    nonisolated static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Asks the server. Only called when the shape already passes, so a
    /// malformed handle never costs a round trip.
    /// The candidate is a PARAMETER, bound by the caller when the check is
    /// scheduled — not read from `typed` in here.
    ///
    /// Reading it here looked equivalent and was not: the debounced task runs
    /// after the user has typed on, so `typed` is already the new value by the
    /// time this body executes, and the staleness guard below compared a value
    /// to itself. It could never fire, which made the protection decorative
    /// and let a slow answer for an abandoned handle label the new one. Caught
    /// by the test that was meant to prove the guard worked.
    public func checkAvailability(for candidate: String) async {
        guard verdict == .checking, candidate == typed else { return }
        do {
            let free = try await store.isAvailable(candidate)
            // Ignore a late answer for a handle the user has moved on from.
            guard candidate == typed else { return }
            verdict = free ? .available : .unavailable
        } catch {
            guard candidate == typed else { return }
            errorMessage = Self.message(for: error)
        }
    }

    public func claim() async {
        guard verdict.isClaimable, !isClaiming else { return }
        isClaiming = true
        errorMessage = nil
        defer { isClaiming = false }
        do {
            claimed = try await store.claim(typed)
        } catch {
            errorMessage = Self.message(for: error)
            // The server refused something the availability check allowed —
            // someone else claimed it in between, or a rule the check does not
            // cover. Either way the field must stop offering the button.
            verdict = .unavailable
        }
    }

    nonisolated static func message(for error: Error) -> String {
        (error as? GlossedError)?.userMessage ?? "that didn't work. try again."
    }

    /// What the field says under the input.
    public var helperText: String {
        switch verdict {
        case .empty: "letters, numbers, dots and underscores."
        case .tooShort: "a bit longer — at least two characters."
        case .badCharacters: "letters, numbers, dots and underscores only, starting with a letter or number."
        case .checking: "checking…"
        case .available: "@\(typed) is free."
        case .unavailable: "@\(typed) isn't available."
        }
    }

    /// Shown after a successful claim.
    ///
    /// The handle is live IMMEDIATELY: `public_profile` returns `h.handle`
    /// unfiltered by moderation state, so a stranger can reach the profile at
    /// once. Its `public_texts` row is a retrospective moderation record, not
    /// a gate (GLO-187).
    public var claimedText: String {
        "@\(claimed ?? typed) is yours, and it's live — people can find you at it now."
    }
}
