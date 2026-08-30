import DataKit
import Foundation

public struct SafetyActionsStore: Sendable {
    public var report: @Sendable (ReportSubject, UUID?, UUID?, ReportReason, String?) async throws -> Void
    public var block: @Sendable (UUID) async throws -> Void

    public init(
        report: @escaping @Sendable (ReportSubject, UUID?, UUID?, ReportReason, String?) async throws -> Void,
        block: @escaping @Sendable (UUID) async throws -> Void
    ) {
        self.report = report
        self.block = block
    }

    public static func live(_ repository: SafetyRepository) -> SafetyActionsStore {
        SafetyActionsStore(
            report: { try await repository.report(
                subject: $0, subjectID: $1, subjectUserID: $2, reason: $3, detail: $4
            ) },
            block: { try await repository.block($0) }
        )
    }
}

@MainActor
@Observable
public final class ReportModel {
    public private(set) var reason: ReportReason?
    public var detail: String = ""
    public private(set) var isSending = false
    public private(set) var sent = false
    public private(set) var didBlock = false
    public private(set) var errorMessage: String?

    /// Offered alongside the report, defaulted off. Blocking is the part that
    /// takes effect now, so it is presented as a choice rather than performed
    /// silently on the reporter's behalf.
    public var alsoBlock = false

    private let store: SafetyActionsStore
    private let subject: ReportSubject
    private let subjectID: UUID?
    private let subjectUserID: UUID?

    public init(
        store: SafetyActionsStore,
        subject: ReportSubject,
        subjectID: UUID? = nil,
        subjectUserID: UUID? = nil
    ) {
        self.store = store
        self.subject = subject
        self.subjectID = subjectID
        self.subjectUserID = subjectUserID
    }

    public var canSend: Bool {
        reason != nil && !isSending
    }

    /// Blocking needs someone to block. Reporting a collection carries no
    /// subject user, so the option is not offered there.
    public var canBlock: Bool {
        subjectUserID != nil
    }

    public func choose(_ reason: ReportReason) {
        self.reason = reason
    }

    public func send() async {
        guard let reason, !isSending else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await store.report(
                subject, subjectID, subjectUserID, reason,
                detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : detail
            )
            // The block is a second write and can fail on its own. Reporting
            // succeeded either way, and the confirmation says which happened.
            if alsoBlock, let subjectUserID {
                try await store.block(subjectUserID)
                didBlock = true
            }
            sent = true
        } catch {
            errorMessage = (error as? GlossedError)?.userMessage ?? "that didn't send. try again."
        }
    }

    /// What actually happens next, which is currently not much.
    ///
    /// Moderation is parked (Sean, Aug 29): the runbook is non-operative and
    /// nobody works the queue. So a report is **stored, not reviewed**, and
    /// promising a review would be a promise the system cannot keep. Blocking
    /// is the part that takes effect immediately, which is why the copy leads
    /// with it when it happened.
    public var outcomeLine: String {
        if didBlock {
            return "blocked. they can't see you or reach you, and you won't see them."
        }
        return "recorded. we're not reviewing reports yet, so blocking is the thing that takes effect now."
    }
}
