import Foundation
import Supabase

// The owner's after-the-fact writes (Sean, Aug 31: "edit a look by clicking
// into it… images cannot be altered, but products can… archive a look").
// Split from `LooksRepository.swift` for the 300-line ceiling, the same split
// `LooksWireRows.swift` is. Opened under the GLO-272 frozen-core grant.
//
// What is deliberately NOT here: photo writes. The ruling makes images
// immutable after the composer, so no method can touch `look_photos` — an
// edit that needs different photos is a new look.

public extension LooksRepository {
    /// Archive and its undo (0053): who may read this look, per ITEM.
    ///
    /// Orthogonal to `state` on purpose — archiving does not unpost, so the
    /// look keeps its `posted_at` and comes straight back when the scope
    /// widens again. `visibility` rides its own column grant (0053 added it;
    /// 0048's UPDATE grant was column-scoped and would have refused this).
    func setVisibility(lookID: UUID, to scope: PrivacyScope) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("looks")
                .update(VisibilityUpdate(visibility: scope))
                .eq("id", value: lookID.uuidString)
                .execute()
        }
    }

    /// `publish`'s inverse: back to `draft`. The `looks_stamp_posted_at`
    /// trigger clears `posted_at` when state leaves `public`, so an unposted
    /// look re-posted later gets a fresh stamp — that is the trigger's rule,
    /// not this method's.
    func unpost(lookID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("looks")
                .update(StateUpdate(state: .draft))
                .eq("id", value: lookID.uuidString)
                .execute()
        }
    }

    /// One column, nullable — an empty caption is nil, not `""`, matching
    /// what the composer writes.
    func updateCaption(lookID: UUID, to caption: String?) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("looks")
                .update(CaptionUpdate(caption: caption))
                .eq("id", value: lookID.uuidString)
                .execute()
        }
    }

    /// Replaces every spot on the given photos with the draft's set — the
    /// edit screen's "products can change". Delete-then-insert because none
    /// of the tag tables carries an UPDATE policy ("moving a pin is a delete
    /// and an insert", 0049); the delete cascades `look_tag_variants` away.
    ///
    /// `photoIDs` must be the look's own photos, from the `MyLook` in hand —
    /// the delete is pinned to them (GLO-258's rule: scope by ids you already
    /// own, don't lean on RLS alone). Not atomic across the two statements: a
    /// failure between them leaves the photos bare, and the caller's retry
    /// with the SAME spots re-lands them (client-minted ids, `ignoreDuplicates`
    /// — the `saveDraft` contract).
    func replaceSpots(
        photoIDs: [UUID], with spots: [LookDraft.Spot]
    ) async throws(GlossedError) {
        _ = try await client.requireUserID()
        guard !photoIDs.isEmpty else { return }
        try await run {
            _ = try await client.supabase
                .from("look_tags")
                .delete()
                .in("look_photo_id", values: photoIDs.map(\.uuidString))
                .execute()
            if !spots.isEmpty {
                let spotRows = spots.map {
                    TagSpotRow(id: $0.id, lookPhotoID: $0.photoID, x: $0.x, y: $0.y)
                }
                try await client.supabase
                    .from("look_tags")
                    .upsert(spotRows, onConflict: "id", ignoreDuplicates: true)
                    .execute()
                let variantRows = spots.flatMap { spot in
                    spot.products.map {
                        TagVariantRow(lookTagID: spot.id, variantID: $0.variantID, position: $0.position)
                    }
                }
                if !variantRows.isEmpty {
                    try await client.supabase
                        .from("look_tag_variants")
                        .upsert(variantRows, onConflict: "look_tag_id,variant_id", ignoreDuplicates: true)
                        .execute()
                }
            }
        }
    }

    /// Swaps ONE photo's bytes (0054, the photo-swap ruling): the row —
    /// its id, position, and every tag pinned to it — survives; only
    /// `r2_key` moves, which is also all the column grant admits. The old
    /// object orphans for the sweep, cutouts' lifecycle.
    ///
    /// Called AFTER the new bytes landed in R2 (the pipeline's order), so
    /// the row never points at an object that does not exist.
    func swapPhotoKey(photoID: UUID, to r2Key: String) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("look_photos")
                .update(PhotoKeySwap(r2Key: r2Key))
                .eq("id", value: photoID.uuidString)
                .execute()
        }
    }

    /// HARD delete — unlike routines and collections, `looks` has no
    /// `deleted_at`, so this is the row gone, photos, spots and links
    /// cascading with it (`looks_delete_own`). The R2 objects behind the
    /// photo keys are orphaned, not removed: the client holds no R2
    /// credential (ADR 0004), and reaping orphans is a server-side job the
    /// backlog carries. The UI's "warns of lost progress" is this method's
    /// only undo.
    func delete(lookID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("looks")
                .delete()
                .eq("id", value: lookID.uuidString)
                .execute()
        }
    }

    /// One column each, typed for the same reason `StateUpdate` is: the keys
    /// are testable, so a payload that grows a column `authenticated` may not
    /// write fails in Swift rather than as a `42501`.
    internal struct VisibilityUpdate: Encodable, Sendable {
        let visibility: PrivacyScope
    }

    /// Encodes `caption` even when nil — a plain optional would OMIT the key,
    /// and PostgREST leaves an unsent column untouched, so "clear the
    /// caption" would silently do nothing.
    struct PhotoKeySwap: Encodable, Sendable {
        let r2Key: String

        enum CodingKeys: String, CodingKey {
            case r2Key = "r2_key"
        }
    }

    internal struct CaptionUpdate: Encodable, Sendable {
        let caption: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(caption, forKey: .caption)
        }

        enum CodingKeys: String, CodingKey {
            case caption
        }
    }
}
