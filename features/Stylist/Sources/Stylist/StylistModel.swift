import DataKit
import Foundation

/// The thread, in the app's memory for the tab's life and nowhere else
/// (08 §3: no transcript table). Turn-at-a-time: a send appends the user's
/// words, waits, appends the stylist's reply with its artifacts.
@MainActor
@Observable
public final class StylistModel {
    public enum Phase: Sendable, Equatable {
        /// Ready for a message.
        case idle
        /// A turn is in flight.
        case thinking
        /// 08 §3 — adults only until Sean rules on minors.
        case notYet
        /// No key on this stack; the tab says so instead of spinning.
        case unconfigured
    }

    public struct Message: Identifiable, Sendable, Equatable {
        public enum Role: Sendable, Equatable {
            case user, stylist
        }

        public let id: UUID
        public let role: Role
        public let text: String
        public let blocks: [StylistBlock]
        public let groundedIn: [String]
        /// True on the user's message that is still waiting for its reply,
        /// or whose reply failed — the retry lives on it.
        public var isPending: Bool

        public init(
            id: UUID = UUID(), role: Role, text: String, blocks: [StylistBlock] = [],
            groundedIn: [String] = [], isPending: Bool = false
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.blocks = blocks
            self.groundedIn = groundedIn
            self.isPending = isPending
        }
    }

    /// The first open's chips — what the stylist can do, phrased as what the
    /// person would say. Replaced by the stylist's own after the first turn.
    public static let starterChips = [
        "build my am routine",
        "build my pm routine",
        "what's missing for my skin",
        "do my products clash?",
        "what should I try next"
    ]

    public private(set) var messages: [Message] = []
    public private(set) var chips: [String] = StylistModel.starterChips
    public private(set) var phase: Phase = .idle
    public private(set) var errorMessage: String?
    /// Routine cards saved this session, each with the id the save minted —
    /// the card says so, and offers the door onto the routine it now is.
    public private(set) var savedRoutines: [RoutineDraftBlock: UUID] = [:]
    public private(set) var savingRoutine: RoutineDraftBlock?
    public var draft = ""

    private let store: StylistStore?
    /// The app's hook for a save that landed: the profile shows routines,
    /// and it must reload for the new one (GLO-278's shape, from a tab
    /// instead of a cover).
    private let onRoutineSaved: ((UUID) -> Void)?
    private(set) var sendTask: Task<Void, Never>?

    public init(store: StylistStore? = nil, onRoutineSaved: ((UUID) -> Void)? = nil) {
        self.store = store
        self.onRoutineSaved = onRoutineSaved
    }

    public var canSend: Bool {
        phase == .idle && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isEmpty: Bool {
        messages.isEmpty
    }

    /// The text-only transcript the server reads, oldest first.
    public var transcript: [StylistTranscriptTurn] {
        messages.filter { !$0.isPending || $0.role == .user }.map {
            StylistTranscriptTurn(role: $0.role == .user ? .user : .assistant, text: $0.text)
        }
    }

    public func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        send(text)
    }

    /// A chip is a message the person chose not to type: same path.
    public func tap(chip: String) {
        send(chip)
    }

    public func send(_ text: String) {
        guard phase == .idle, let store else { return }
        errorMessage = nil
        messages.append(Message(role: .user, text: text, isPending: true))
        phase = .thinking
        let turns = transcript
        sendTask = Task { [weak self] in
            do {
                let reply = try await store.send(turns)
                self?.receive(reply)
            } catch {
                self?.fail(error)
            }
        }
    }

    /// Retries the last message when its reply failed; the words are kept
    /// so nobody retypes them.
    public func retry() {
        guard phase == .idle, let last = messages.last, last.role == .user, last.isPending else { return }
        messages.removeLast()
        send(last.text)
    }

    public func save(routine: RoutineDraftBlock) {
        guard let save = store?.saveRoutine, savingRoutine == nil, savedRoutines[routine] == nil else { return }
        savingRoutine = routine
        errorMessage = nil
        Task { [weak self] in
            do {
                let id = try await save(routine)
                self?.savedRoutines[routine] = id
                self?.onRoutineSaved?(id)
            } catch {
                self?.errorMessage = (error as? GlossedError)?.userMessage ?? "couldn't save that routine."
            }
            self?.savingRoutine = nil
        }
    }

    public var canSaveRoutines: Bool {
        store?.saveRoutine != nil
    }

    private func receive(_ reply: StylistReply) {
        if let index = messages.lastIndex(where: { $0.role == .user && $0.isPending }) {
            messages[index].isPending = false
        }
        messages.append(Message(role: .stylist, text: reply.text, blocks: reply.blocks, groundedIn: reply.groundedIn))
        if !reply.chips.isEmpty {
            chips = reply.chips
        }
        phase = .idle
        store?.track?(reply.toolsUsed, !reply.text.isEmpty || !reply.blocks.isEmpty)
    }

    private func fail(_ error: Error) {
        switch error {
        case StylistError.notYet:
            phase = .notYet
        case StylistError.unconfigured:
            phase = .unconfigured
        default:
            errorMessage = (error as? GlossedError)?.userMessage ?? "the stylist couldn't answer just now."
            phase = .idle
        }
        store?.track?([], false)
    }
}
