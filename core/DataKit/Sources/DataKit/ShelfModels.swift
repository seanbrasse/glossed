import Foundation

// The shelf's public models, lifted out of `ShelfRepository.swift` for the
// reason `RoutinesModels.swift` and `CollectionsModels.swift` exist: the
// repository sat one line under SwiftLint's 300-line ceiling, and a file at the
// ceiling is a landmine for whoever adds the next line — `AppShell.swift` was
// broken that way by two green PRs merging minutes apart (handoff §0). The
// internal wire shapes stay in `ShelfWireRows.swift`; this is what callers hold.

public struct LogDraft: Sendable {
    public let variantID: UUID
    public let status: ItemStatus
    public let startedOn: Date?
    public let note: String?
    /// Client-generated so a retry resolves to the same row.
    public let clientID: UUID

    public init(
        variantID: UUID,
        status: ItemStatus = .own,
        startedOn: Date? = nil,
        note: String? = nil,
        clientID: UUID = UUID()
    ) {
        self.variantID = variantID
        self.status = status
        self.startedOn = startedOn
        self.note = note
        self.clientID = clientID
    }

    func row(userID: UUID) -> LogRow {
        LogRow(
            userID: userID.uuidString,
            variantID: variantID.uuidString,
            status: status.rawValue,
            startedOn: startedOn.map { $0.formatted(.iso8601.year().month().day()) },
            note: note,
            clientID: clientID.uuidString
        )
    }
}
