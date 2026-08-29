import Foundation
import os

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

/// What a dropped batch tells whoever is watching: how many events died and
/// what killed them. Never the events themselves — a drop notice is a
/// diagnostic, and props can carry regulated data (domain.md §5).
public typealias DropObserver = @Sendable (Int, any Error) -> Void

/// The reason a batch died when nothing threw: the queue filled and the
/// oldest events made way. It is not a transport failure, but it is a drop,
/// and a counter that omitted it would lie by exactly the omission this
/// ticket is about.
public struct TrackerOverCapacity: Error, Equatable, Sendable {
    public let cap: Int
}

/// The `track()` wrapper. An actor: events arrive from any screen.
public actor Tracker {
    /// Above this the queue flushes itself rather than waiting for the app
    /// lifecycle — a long session should not hold hundreds of events hostage.
    public static let flushThreshold = 20

    /// The queue's hard cap. Beyond it the *oldest* events drop first: recent
    /// behavior is worth more than a backlog nobody could deliver.
    public static let capacity = 500

    /// The default voice for a dropped batch (GLO-147): a line in the unified
    /// log in DEBUG, and nothing whatsoever in release. The drop is correct —
    /// the silence around it is not: without a word, a drive cannot tell
    /// working instrumentation from instrumentation that is stone dead, and
    /// driving is how we find defects.
    ///
    /// `Logger` and not `print` for one reason, learned the hard way: `print`
    /// goes to stdout, which is only visible if the app was launched with
    /// `simctl launch --console`, and the project's own launch recipe does
    /// not. A signal a driver cannot reach is the bug this ticket is about
    /// wearing a different coat. This one shows up in
    /// `xcrun simctl spawn <udid> log stream --predicate
    /// 'subsystem == "com.glossed.tracking"'` however the app was started.
    ///
    /// `String(describing:)` and not `localizedDescription`, also learned by
    /// looking: an `Error` with no `LocalizedError` conformance renders as
    /// "The operation couldn't be completed. (DataKit.GlossedError error 1.)",
    /// which names neither the status nor the endpoint. A reason a driver
    /// cannot read is the same defect this ticket is about. Only the
    /// transport's error is ever printed — never an event or its props, which
    /// can carry regulated data (domain.md §5).
    public static let logDropObserver: DropObserver = { count, error in
        #if DEBUG
            let reason = String(describing: error)
            Logger(subsystem: "com.glossed.tracking", category: "drops")
                .error("analytics dropped \(count, privacy: .public) event(s): \(reason, privacy: .public)")
        #endif
    }

    private let poster: EventPosting
    private let screenProvider: @Sendable () -> String?
    private let onDrop: DropObserver
    private var queue: [QueuedEvent] = []
    private var isFlushing = false

    public init(
        poster: EventPosting,
        screen: @escaping @Sendable () -> String? = { nil },
        onDrop: @escaping DropObserver = Tracker.logDropObserver
    ) {
        self.poster = poster
        screenProvider = screen
        self.onDrop = onDrop
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
            let shed = queue.count - Tracker.capacity
            queue.removeFirst(shed)
            droppedCount += shed
            onDrop(shed, TrackerOverCapacity(cap: Tracker.capacity))
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
            // the queue until the cap ate the *newest* session's events. Said
            // out loud, though (GLO-147) — a silent drop is indistinguishable
            // from working instrumentation, and the observer costs nothing in
            // release.
            droppedCount += batch.count
            onDrop(batch.count, error)
        }
    }

    /// What is waiting, for tests and the debug screen.
    public var pendingCount: Int {
        queue.count
    }

    /// How many events this tracker has thrown away, cumulative. The number a
    /// drive can check when it wants to know whether "no events" means the
    /// code is wrong or the endpoint is simply not there.
    public private(set) var droppedCount = 0
}
