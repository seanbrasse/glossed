import Foundation
import Supabase

/// A linked thing, as a row renders it: enough to draw a chip and open the
/// real object, nothing more. One shape for all three pairs — what differs
/// between them is which TABLE and which visibility function answer, and both
/// of those live in the schema (0050, 0052), not here.
public struct LinkedItem: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

/// Everything a look links (0050): the routines and collections its owner
/// attached. Both lists are in `position` order.
public struct LookLinks: Sendable, Equatable {
    public let routines: [LinkedItem]
    public let collections: [LinkedItem]

    public var isEmpty: Bool {
        routines.isEmpty && collections.isEmpty
    }

    public init(routines: [LinkedItem], collections: [LinkedItem]) {
        self.routines = routines
        self.collections = collections
    }
}

/// Reads and writes for the three link pairs — look→routine, look→collection
/// (0050) and routine→collection (0052). Opened under Sean's Aug 31 build
/// order ("link looks, collections, and routines together"), the same
/// session's grant as the 0049 reshape.
///
/// **Writes are own-only end to end** — the policies enforce it (a link may
/// not annex somebody else's routine or collection), so these methods do not
/// re-check; they surface the `42501` as a `GlossedError` like every other
/// refused write.
///
/// **Reads lean on the both-halves rule** rather than re-implementing it: the
/// public read policies show a link only where both ends are independently
/// visible, so whatever comes back is renderable, and a row that would leak
/// an `only_you` title never arrives. pgTAP owns that proof
/// (`look_links.test.sql`, `routine_collection_links.test.sql`).
///
/// `ignoreDuplicates` on every insert: none of the three tables has an UPDATE
/// policy (a reorder is a delete and an insert — 0050's rule), so an upsert
/// resolving to DO UPDATE dies as `42501` on exactly the retry path upsert
/// exists for.
public struct LinksRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    // MARK: - a look's links (0050)

    public func link(lookID: UUID, routineIDs: [UUID], collectionIDs: [UUID]) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            if !routineIDs.isEmpty {
                let rows = routineIDs.enumerated().map { index, id in
                    LookRoutineRow(lookID: lookID, routineID: id, position: index)
                }
                try await client.supabase
                    .from("look_routines")
                    .upsert(rows, onConflict: "look_id,routine_id", ignoreDuplicates: true)
                    .execute()
            }
            if !collectionIDs.isEmpty {
                let rows = collectionIDs.enumerated().map { index, id in
                    LookCollectionRow(lookID: lookID, collectionID: id, position: index)
                }
                try await client.supabase
                    .from("look_collections")
                    .upsert(rows, onConflict: "look_id,collection_id", ignoreDuplicates: true)
                    .execute()
            }
        }
    }

    /// What this look links, titles resolved through PostgREST embedding —
    /// the embedded `routines`/`collections` read runs under the same RLS as
    /// any other, so a title the caller may not read simply does not embed,
    /// and the row is dropped rather than rendered blank.
    public func links(lookID: UUID) async throws(GlossedError) -> LookLinks {
        let routineRows: [EmbeddedRoutineRow] = try await run {
            try await client.supabase
                .from("look_routines")
                .select("routine_id,position,routines(title)")
                .eq("look_id", value: lookID.uuidString)
                .order("position")
                .execute()
                .value
        }
        let collectionRows: [EmbeddedCollectionRow] = try await run {
            try await client.supabase
                .from("look_collections")
                .select("collection_id,position,collections(title)")
                .eq("look_id", value: lookID.uuidString)
                .order("position")
                .execute()
                .value
        }
        return LookLinks(
            routines: routineRows.compactMap { row in
                row.routines.map { LinkedItem(id: row.routineID, title: $0.title) }
            },
            collections: collectionRows.compactMap { row in
                row.collections.map { LinkedItem(id: row.collectionID, title: $0.title) }
            }
        )
    }

    // MARK: - a routine's collections (0052)

    public func link(routineID: UUID, collectionIDs: [UUID]) async throws(GlossedError) {
        _ = try await client.requireUserID()
        guard !collectionIDs.isEmpty else { return }
        try await run {
            let rows = collectionIDs.enumerated().map { index, id in
                RoutineCollectionRow(routineID: routineID, collectionID: id, position: index)
            }
            try await client.supabase
                .from("routine_collections")
                .upsert(rows, onConflict: "routine_id,collection_id", ignoreDuplicates: true)
                .execute()
        }
    }

    public func linkedCollections(routineID: UUID) async throws(GlossedError) -> [LinkedItem] {
        let rows: [EmbeddedCollectionRow] = try await run {
            try await client.supabase
                .from("routine_collections")
                .select("collection_id,position,collections(title)")
                .eq("routine_id", value: routineID.uuidString)
                .order("position")
                .execute()
                .value
        }
        return rows.compactMap { row in
            row.collections.map { LinkedItem(id: row.collectionID, title: $0.title) }
        }
    }

    // MARK: - unlink (Sean's Aug 31 follow-up: the composers only add)

    /// Deletes ride the pair's primary key and the tables' own delete
    /// policies (own-only), so an unlink of somebody else's link deletes
    /// zero rows rather than erroring — RLS filters, it does not throw.
    /// Idempotent for the same reason: unlinking twice is one row gone.
    public func unlink(lookID: UUID, routineID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("look_routines")
                .delete()
                .eq("look_id", value: lookID.uuidString)
                .eq("routine_id", value: routineID.uuidString)
                .execute()
        }
    }

    public func unlink(lookID: UUID, collectionID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("look_collections")
                .delete()
                .eq("look_id", value: lookID.uuidString)
                .eq("collection_id", value: collectionID.uuidString)
                .execute()
        }
    }

    public func unlink(routineID: UUID, collectionID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("routine_collections")
                .delete()
                .eq("routine_id", value: routineID.uuidString)
                .eq("collection_id", value: collectionID.uuidString)
                .execute()
        }
    }

    /// Every routine's linked collections in ONE read, for a grid of cards —
    /// N per-card queries is how a six-routine tab issues six round trips.
    /// Grouped by routine, each group in `position` order.
    public func linkedCollections(routineIDs: [UUID]) async throws(GlossedError) -> [UUID: [LinkedItem]] {
        guard !routineIDs.isEmpty else { return [:] }
        let rows: [EmbeddedRoutineCollectionRow] = try await run {
            try await client.supabase
                .from("routine_collections")
                .select("routine_id,collection_id,position,collections(title)")
                .in("routine_id", values: routineIDs.map(\.uuidString))
                .order("position")
                .execute()
                .value
        }
        return Dictionary(grouping: rows, by: \.routineID)
            .mapValues { group in
                group.compactMap { row in
                    row.collections.map { LinkedItem(id: row.collectionID, title: $0.title) }
                }
            }
    }

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}
