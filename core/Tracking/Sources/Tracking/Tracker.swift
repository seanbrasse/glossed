import Foundation

// The client half of tech/06 §2: a buffered queue in front of an injected
// transport. The rules, verbatim from the spec, each carried by a test:
//
// - flushed on background/foreground (the app calls `flush()` at both)
// - **dropped, not blocked, on failure** — analytics must never cost UX
// - client-generated event UUIDs dedupe retries server-side

/// One event, stamped and ready for the wire.
public struct QueuedEvent: Sendable, Equatable {
    /// Client-generated: a retry after a dropped connection re-sends the same
    /// id and the ingest's upsert makes it a no-op.
    public let id: UUID
    public let name: String
    public let props: [String: PropValue]
    public let screen: String?
    public let occurredAt: Date

    /// The wire shape, as `track_ingest` reads it.
    public func payload() -> [String: Any] {
        var body: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "name": name,
            "ts": occurredAt.timeIntervalSince1970
        ]
        body["props"] = props.reduce(into: [String: Any]()) { partial, entry in
            if let value = entry.value.jsonValue {
                partial[entry.key] = value
            }
        }
        if let screen {
            body["screen"] = screen
        }
        return body
    }
}

/// What the tracker hands a batch to. The app wires this to the
/// `track_ingest` Edge Function; tests wire it to an array.
public protocol EventPosting: Sendable {
    /// Returns normally on success; throws on any failure. The tracker treats
    /// every failure the same way — the batch is gone.
    func post(_ batch: [QueuedEvent]) async throws
}

/// The `track()` wrapper. An actor: events arrive from any screen.
public actor Tracker {
    /// Above this the queue flushes itself rather than waiting for the app
    /// lifecycle — a long session should not hold hundreds of events hostage.
    public static let flushThreshold = 20

    /// The queue's hard cap. Beyond it the *oldest* events drop first: recent
    /// behavior is worth more than a backlog nobody could deliver.
    public static let capacity = 500

    private let poster: EventPosting
    private let screenProvider: @Sendable () -> String?
    private var queue: [QueuedEvent] = []
    private var isFlushing = false

    public init(poster: EventPosting, screen: @escaping @Sendable () -> String? = { nil }) {
        self.poster = poster
        screenProvider = screen
    }

    /// The one call sites make. Never throws, never blocks the caller on IO.
    public func track(_ event: Event, at occurredAt: Date = Date()) {
        queue.append(QueuedEvent(
            id: UUID(),
            name: event.name,
            props: event.props,
            screen: screenProvider(),
            occurredAt: occurredAt
        ))
        if queue.count > Tracker.capacity {
            queue.removeFirst(queue.count - Tracker.capacity)
        }
        if queue.count >= Tracker.flushThreshold {
            Task { await flush() }
        }
    }

    /// Sends everything queued. Called by the app on background/foreground and
    /// by the threshold above. On failure the batch is dropped — the whole
    /// point is that analytics can never wedge the app behind a retry loop;
    /// the ingest's id-dedupe makes the *successful* retry path safe, not this.
    public func flush() async {
        guard !isFlushing, !queue.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        let batch = queue
        queue.removeAll()
        do {
            try await poster.post(batch)
        } catch {
            // Dropped, deliberately. Not re-queued: a dead endpoint would grow
            // the queue until the cap ate the *newest* session's events.
        }
    }

    /// What is waiting, for tests and the debug screen.
    public var pendingCount: Int {
        queue.count
    }
}
