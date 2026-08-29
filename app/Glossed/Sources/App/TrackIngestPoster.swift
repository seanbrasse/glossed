import DataKit
import Foundation
import Tracking

/// The glue tech/06 §2 leaves to the app: Tracking's queue on one side,
/// DataKit's transport on the other, neither knowing the other exists.
/// Tracking cannot grow a path to the data layer, and DataKit never sees an
/// event shape — this struct is the whole seam, and it fits on a screen.
struct TrackIngestPoster: EventPosting {
    let client: GlossedClient

    /// Throws on any failure and lets the tracker do the deciding: the batch
    /// is dropped there, never retried here — analytics must not cost UX.
    func post(_ batch: [QueuedEvent]) async throws {
        let body: [String: Any] = ["events": batch.map { $0.payload() }]
        let data = try JSONSerialization.data(withJSONObject: body)
        try await client.invokeEdgeFunction("track_ingest", jsonBody: data)
    }
}
