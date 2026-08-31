import Foundation
import Supabase

/// Your own collections: create, rename, retract, and put things in or take
/// them out. Sean's V1 scope, verbatim — "create, rename, add/remove products".
///
/// **A collection groups things you OWN.** `collection_items.user_item_id`
/// references `user_items`, never `products` or `variants`, and
/// `collection_items_own`'s `WITH CHECK` requires the item be yours as well as
/// the collection. A variant id handed to `addItem` is refused by the foreign
/// key, not silently stored — so the picker for this is built off the shelf.
///
/// **Privacy is a column here, unlike routines.** `collections.visibility` is a
/// `scope_enum` defaulting to `only_you`, and `collection_is_visible()` reads
/// it — plus block, minor status and mutual-follow — to answer for everyone
/// else. Nothing in this repository widens it: creating a collection does not
/// publish it, and V1 ships no call that changes the scope.
public struct CollectionsRepository: Sendable {
    private let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    /// Your collections, newest first, each carrying the n its card renders.
    ///
    /// Three reads rather than one RPC, the same shape `RoutinesRepository.mine`
    /// uses: the third goes through `user_shelf_items`, which is
    /// `security_invoker` and filters `deleted_at is null` itself. That is what
    /// makes `itemN` the count of what the collection will actually DRAW —
    /// see `assemble`.
    ///
    /// **`user_id` is pinned in the query, and RLS is not what makes this
    /// "mine".** `collections` carries TWO select policies — `collections_own`
    /// and `collections_public` — and Postgres OR's policies for the same
    /// command. So an unfiltered select returns your own rows *plus* every
    /// collection `collection_is_visible()` says you may read, which is
    /// somebody else's card in your own grid.
    ///
    /// Probed, not reasoned: as user A, `select … from collections where
    /// deleted_at is null` returned "A own collection + B public collection".
    /// The predicate below is what makes the name on this function true.
    public func mine() async throws(GlossedError) -> [MyCollection] {
        let userID = try await client.requireUserID()
        let collections: [OwnCollectionRow] = try await run {
            try await client.supabase
                .from("collections")
                .select("id,title,cover_tint,visibility,created_at")
                .eq("user_id", value: userID.uuidString)
                .is("deleted_at", value: nil)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
        guard !collections.isEmpty else { return [] }

        let members: [MemberRow] = try await run {
            try await client.supabase
                .from("collection_items")
                .select("collection_id,user_item_id,position")
                .in("collection_id", values: collections.map(\.id.uuidString))
                .order("position")
                .execute()
                .value
        }
        let live = try await liveItemIDs(among: members.map(\.userItemID))
        return CollectionsRepository.assemble(collections: collections, members: members, live: live)
    }

    /// The collection's contents, in `position` order, as shelf rows.
    ///
    /// Returns what the collection can actually draw: `user_shelf_items` drops
    /// an item whose shelf entry was soft-deleted, and the membership row for
    /// it is skipped rather than rendered as a gap — the same choice
    /// `RoutinesRepository.mine` makes for an unreadable step.
    ///
    /// **Handed somebody else's public collection id, this returns `[]` rather
    /// than their shelf.** `collection_items_public` would let the first read
    /// see their membership rows, but the second goes through
    /// `user_shelf_items`, which is `security_invoker` and so answers only for
    /// YOUR shelf — their `user_items` are not yours, so every row is dropped
    /// by `ordered`. Stated rather than left to be rediscovered: the safety
    /// here is the view's, not this function's.
    public func items(collectionID: UUID) async throws(GlossedError) -> [ShelfRow] {
        _ = try await client.requireUserID()
        let members: [MemberRow] = try await run {
            try await client.supabase
                .from("collection_items")
                .select("collection_id,user_item_id,position")
                .eq("collection_id", value: collectionID.uuidString)
                .order("position")
                .execute()
                .value
        }
        guard !members.isEmpty else { return [] }

        let rows: [ShelfRow] = try await run {
            try await client.supabase
                .from("user_shelf_items")
                .select()
                .in("user_item_id", values: members.map(\.userItemID.uuidString))
                .execute()
                .value
        }
        return CollectionsRepository.ordered(rows, by: members)
    }

    /// Creates a collection. The caller mints the PRIMARY KEY, so a retry after
    /// a failed create upserts the same row rather than leaving two collections
    /// wearing the same name — the `RoutineDraft` / `LookDraft` pattern.
    ///
    /// `visibility` is deliberately not a parameter: the column defaults to
    /// `only_you`, and a create call that could also publish is a create call
    /// that publishes by accident.
    @discardableResult
    public func create(
        title: String,
        tint: CollectionTint? = nil,
        collectionID: UUID = UUID()
    ) async throws(GlossedError) -> UUID {
        let userID = try await client.requireUserID()
        let trimmed = try CollectionsRepository.requireTitle(title)
        let row = NewCollectionRow(
            id: collectionID, userID: userID, title: trimmed, coverTint: tint?.rawValue
        )
        return try await run {
            let inserted: InsertedID = try await client.supabase
                .from("collections")
                .upsert(row, onConflict: "id")
                .select("id")
                .single()
                .execute()
                .value
            return inserted.id
        }
    }

    /// Renames a collection. **Half of a rename, exactly as routines is.**
    ///
    /// `collections.title` is the owner's copy. `public_texts` carries a
    /// `collection_title` kind whose `subject_id` is the collection, and that
    /// is the string a public surface would be allowed to read. Nothing browses
    /// collections today, so nothing reads it yet — but a caller that makes a
    /// collection public must also call `SafetyRepository.submitPublicText`,
    /// because this write does not.
    public func rename(collectionID: UUID, to title: String) async throws(GlossedError) {
        _ = try await client.requireUserID()
        let trimmed = try CollectionsRepository.requireTitle(title)
        try await run {
            _ = try await client.supabase
                .from("collections")
                .update(CollectionTitleUpdate(title: trimmed, updatedAt: Date().ISO8601Format()))
                .eq("id", value: collectionID.uuidString)
                .execute()
        }
    }

    /// Who may read this collection — the same write the routines and looks
    /// controls make since 0053, though `collections.visibility` predates
    /// them (0021). A caller widening past `.onlyYou` owns the
    /// `submitPublicText` obligation `rename` documents; this write does not
    /// perform it.
    public func setVisibility(collectionID: UUID, to scope: PrivacyScope) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("collections")
                .update(CollectionScopeUpdate(visibility: scope, updatedAt: Date().ISO8601Format()))
                .eq("id", value: collectionID.uuidString)
                .execute()
        }
    }

    /// Soft delete — `collection_is_visible()` tests `deleted_at is null`
    /// (probed in the function body), so setting it is what actually retracts
    /// the collection. A hard delete would cascade every `collection_items` row
    /// away, and losing the grouping is not what "delete this card" means.
    public func remove(collectionID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("collections")
                .update(["deleted_at": Date().ISO8601Format()])
                .eq("id", value: collectionID.uuidString)
                .execute()
        }
    }

    /// Puts one of your shelf items into one of your collections.
    ///
    /// Idempotent by primary key: `(collection_id, user_item_id)` means adding
    /// the same item twice re-positions it rather than duplicating it, which is
    /// also why a product can appear in a collection only once.
    public func addItem(
        collectionID: UUID, itemID: UUID, position: Int = 0
    ) async throws(GlossedError) {
        _ = try await client.requireUserID()
        let row = MemberWriteRow(
            collectionID: collectionID, userItemID: itemID, position: position
        )
        try await run {
            _ = try await client.supabase
                .from("collection_items")
                .upsert(row, onConflict: "collection_id,user_item_id")
                .execute()
        }
    }

    /// Takes an item back out. A hard delete on purpose, for the reason
    /// `ShelfRepository.removeChip` gives: nothing points at a membership row,
    /// the table has no `deleted_at` (probed), and a soft-deleted row would
    /// still occupy the `(collection_id, user_item_id)` primary key — so
    /// re-adding an item you removed would conflict instead of working.
    ///
    /// The item itself is untouched. Taking a lipstick out of "spring" does not
    /// take it off your shelf.
    public func removeItem(collectionID: UUID, itemID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("collection_items")
                .delete()
                .eq("collection_id", value: collectionID.uuidString)
                .eq("user_item_id", value: itemID.uuidString)
                .execute()
        }
    }

    private func liveItemIDs(among itemIDs: [UUID]) async throws(GlossedError) -> Set<UUID> {
        guard !itemIDs.isEmpty else { return [] }
        let rows: [LiveItemRow] = try await run {
            try await client.supabase
                .from("user_shelf_items")
                .select("user_item_id")
                .in("user_item_id", values: itemIDs.map(\.uuidString))
                .execute()
                .value
        }
        return Set(rows.map(\.userItemID))
    }

    private func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}
