import DataKit
import Foundation
import Observation

/// How the handle step reaches persistence. A closure seam, not a repository,
/// for the reason every other seam in this package is one: features never
/// import features, and the model is driven in tests with no client present.
public struct OnbHandleStore: Sendable {
    public var isAvailable: @Sendable (String) async throws -> Bool
    public var claim: @Sendable (String) async throws -> String
    /// The caller's handle, if they have one. Asked first: an account that
    /// already has a handle does not pick another, it carries on. Nil seam
    /// means "ask" — the debug catalog's mount.
    public var existing: (@Sendable () async throws -> String?)?

    public init(
        isAvailable: @escaping @Sendable (String) async throws -> Bool,
        claim: @escaping @Sendable (String) async throws -> String,
        existing: (@Sendable () async throws -> String?)? = nil
    ) {
        self.isAvailable = isAvailable
        self.claim = claim
        self.existing = existing
    }
}

/// What the field can say about what is typed.
/// What the field can say, one case per state the user can be in. The
/// rules are `claim_handle`'s (migration 0023): 2–30 of `a-z 0-9 . _`,
/// starting with a letter or number, no `..` — and the app asks for 3
/// (Sean, Sep 2: *"we need a char minimum"*; two characters is a typo, not
/// a name).
public enum OnbHandleVerdict: Equatable, Sendable {
    case empty
    case tooShort
    /// Why, in the user's words — "start with a letter or number."
    case malformed(String)
    case checking
    case taken
    case available
    /// This account has a handle already; the screen carries on with it.
    case alreadyYours(String)
    case failed(String)
}

@MainActor
@Observable
public final class OnbHandleModel {
    public nonisolated static let minimumLength = 3
    public nonisolated static let maximumLength = 30
    /// The rule, as the screen states it under the field.
    public nonisolated static let rules = "3–30 characters. letters, numbers, dots and underscores."

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
        }.prefix(maximumLength))
    }

    /// Pre-fills from the name, and **only pre-fills**. Asked whether to
    /// auto-assign a handle, the answer is no: an assigned one means
    /// collisions resolved into `maya_k_4821`, which is an identity nobody
    /// chose on the one field the product calls "how people find you". This
    /// costs a tap to accept and nothing to ignore.
    /// The shape rule, applied to a normalized string. Nil means well-formed.
    public nonisolated static func shapeProblem(_ handle: String) -> String? {
        if let first = handle.first, !(first.isLetter || first.isNumber) {
            return "start with a letter or number."
        }
        if handle.contains("..") {
            return "one dot at a time."
        }
        return nil
    }

    /// First thing on the screen. An account that already has a handle is
    /// not asked for another (Sean's phone, Sep 2: his second walk through
    /// signup hit "that's already on your shelf" — the shelf's generic
    /// conflict message — because `handles` allows one row per user and he
    /// had one). It carries on; everyone else gets the suggestion.
    public func start(onClaimed: @escaping () -> Void) {
        guard let existing = store?.existing else {
            suggest()
            return
        }
        checkTask = Task {
            if let mine = try? await existing(), !mine.isEmpty {
                typed = mine
                verdict = .alreadyYours(mine)
                onClaimed()
            } else {
                suggest()
            }
        }
    }

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
        guard typed.count >= Self.minimumLength else {
            verdict = .tooShort
            return
        }
        if let problem = Self.shapeProblem(typed) {
            verdict = .malformed(problem)
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
                verdict = await Self.claimVerdict(for: error, store: store)
                if case .alreadyYours = verdict {
                    onClaimed()
                }
            }
        }
    }

    /// The server's refusals, in the user's words. `claim_handle` raises
    /// `check_violation` for a reserved handle, a brand's name and a minor;
    /// a unique violation is either a race on the handle or this account's
    /// second claim — `handles` allows one per user — and only a re-read of
    /// `existing` tells the two apart. DataKit's generic conflict message
    /// ("that's already on your shelf.") is about shelves and never shown
    /// here.
    static func claimVerdict(for error: Error, store: OnbHandleStore) async -> OnbHandleVerdict {
        let glossed = error as? GlossedError
        let detail = (glossed?.debugDetail ?? String(describing: error)).lowercased()
        if glossed?.code == .conflict || detail.contains("23505") {
            if let mine = try? await store.existing?(), !mine.isEmpty {
                return .alreadyYours(mine)
            }
            return .taken
        }
        if detail.contains("reserved") {
            return .failed("that one\u{2019}s reserved.")
        }
        if detail.contains("brand") {
            return .failed("that\u{2019}s a brand\u{2019}s name \u{2014} pick one that\u{2019}s yours.")
        }
        if detail.contains("public identity") {
            return .failed("handles are for accounts 13 and up.")
        }
        return .failed(glossed?.userMessage ?? "couldn\u{2019}t claim that one. try another.")
    }
}
