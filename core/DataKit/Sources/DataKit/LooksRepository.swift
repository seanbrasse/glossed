import Foundation
import Supabase

/// A draft look as the composer hands it over, in one shape — the repository
/// writes parent and children itself so a caller cannot invent an ordering
/// that leaves a photo-less look row behind on a mid-flight failure.
public struct LookDraft: Sendable {
    public struct Photo: Sendable {
        /// Client-minted, and it is not optional bookkeeping: `look_tags`
        /// keys on `look_photo_id` (0049), so a spot cannot be written unless
        /// the draft knew its photo's id BEFORE the save. Minting here also
        /// keeps the retry idempotent — the same draft re-lands the same row.
        public let id: UUID
        public let r2Key: String
        public let position: Int

        public init(id: UUID = UUID(), r2Key: String, position: Int) {
            self.id = id
            self.r2Key = r2Key
            self.position = position
        }
    }

    /// One product inside a spot. `position` orders the overlay; readers
    /// break ties by `variant_id` (0049's own comment).
    public struct SpotProduct: Sendable {
        public let variantID: UUID
        public let position: Int

        public init(variantID: UUID, position: Int) {
            self.variantID = variantID
            self.position = position
        }
    }

    /// A tag, in Sean's model (GLO-266): a SPOT on one photo, holding several
    /// products. This replaced `Tag(variantID:x:y:)`, which was the 0043 shape
    /// — look-scoped, one product per row — and could express neither half.
    public struct Spot: Sendable {
        /// Client-minted for the same reason `Photo.id` is: `look_tag_variants`
        /// keys on it, and a retry must re-land rather than duplicate.
        public let id: UUID
        /// Must be the `id` of a `Photo` in this same draft — the repository
        /// writes photos first for exactly this dependency.
        public let photoID: UUID
        public let x: Double
        public let y: Double
        public let products: [SpotProduct]

        public init(id: UUID = UUID(), photoID: UUID, x: Double, y: Double, products: [SpotProduct]) {
            self.id = id
            self.photoID = photoID
            self.x = x
            self.y = y
            self.products = products
        }
    }

    public let caption: String?
    public let photos: [Photo]
    public let spots: [Spot]
    /// Idempotency, the LogDraft pattern with 0043's shape: the caller mints
    /// the look's PRIMARY KEY, so a retry after a failed save upserts the same
    /// row rather than minting a duplicate — no client_id column needed.
    public let lookID: UUID

    public init(caption: String?, photos: [Photo], spots: [Spot], lookID: UUID = UUID()) {
        self.caption = caption
        self.photos = photos
        self.spots = spots
        self.lookID = lookID
    }
}

/// Reads and writes for the feed's photo posts (0043, 0048). Session-scoped
/// opening, Aug 30: granted for exactly this repository.
///
/// **A look is born a draft, and its owner publishes it.** `state` is absent
/// from the `authenticated` INSERT grant, so `saveDraft` cannot create anything
/// but a draft; `publish` below is a second, deliberate write.
///
/// **Nothing screens a look before strangers can read it.** That is a decision,
/// not an oversight — Sean's ruling, Aug 30, recorded on GLO-238 and built by
/// migration 0048. GLO-26 carries the moderation stack and the launch gate.
///
/// This comment previously claimed the opposite: *"the state machine's public
/// transition belongs to moderation (GLO-26), and no client write can perform
/// it (RLS: `state` is not client-settable past the insert default)."* **That
/// was never true.** 0043's `looks_update_own` constrained only `user_id` and
/// said nothing about `state`, so an owner could always publish; the comment
/// asserted a guarantee that did not exist, which is what let it survive
/// review. GLO-238 is the ticket, and this is the correction it required.
///
/// What 0048 actually enforces, and what a caller may rely on:
///
/// - `INSERT (id, user_id, caption)` — no `state`, so a look starts as a draft.
/// - `UPDATE (id, user_id, caption, state)` — `id`/`user_id` are there because
///   PostgREST's upsert re-`SET`s every payload column on conflict, which
///   `saveDraft`'s retry path needs; the with-check still pins `user_id` to the
///   caller.
/// - The with-check also pins `state in ('draft', 'public')`, so
///   `pending_review` and `removed` are unreachable from the app.
/// - `posted_at`, `moderation` and `removed_at` were revoked from
///   `authenticated`. Sending any of them raises `42501`.
/// - `can_post_look()` still gates INSERT, so under-18s cannot create a look.
public struct LooksRepository: Sendable {
    /// `internal`, not `private`: `LooksEditing.swift` is the same type split
    /// across files for the 300-line ceiling, and Swift's `private` is
    /// file-scoped.
    let client: GlossedClient

    public init(client: GlossedClient) {
        self.client = client
    }

    private struct InsertedID: Decodable {
        let id: UUID
    }

    /// Parent first, children after. A mid-flight failure cannot duplicate:
    /// the caller still holds the draft, whose lookID is the primary key, so
    /// retrying the SAME draft upserts the same parent and re-lands the
    /// children — resume, not restart.
    public func saveDraft(_ draft: LookDraft) async throws(GlossedError) -> UUID {
        let userID = try await client.requireUserID()
        let lookID: UUID = try await run {
            let inserted: InsertedID = try await client.supabase
                .from("looks")
                .upsert(
                    LookRow(id: draft.lookID, userID: userID, caption: draft.caption),
                    onConflict: "id"
                )
                .select("id")
                .single()
                .execute()
                .value
            return inserted.id
        }
        try await run {
            // Photos first: spots reference them by id (0049), so the order
            // below is a dependency, not a style choice.
            //
            // `ignoreDuplicates` on every child write, and it is load-bearing:
            // NONE of the three child tables carries an UPDATE policy —
            // "moving a pin is a delete and an insert" (0049's comment, and
            // look_photos was always insert/delete/select). An upsert that
            // resolves to DO UPDATE therefore dies as 42501 on the retry path,
            // which is precisely the path upsert exists for. DO NOTHING is the
            // retry that can succeed: rows that landed are skipped, rows that
            // did not are inserted.
            if !draft.photos.isEmpty {
                let rows = draft.photos.map {
                    PhotoRow(id: $0.id, lookID: lookID, r2Key: $0.r2Key, position: $0.position)
                }
                try await client.supabase
                    .from("look_photos")
                    .upsert(rows, onConflict: "id", ignoreDuplicates: true)
                    .execute()
            }
            if !draft.spots.isEmpty {
                let spotRows = draft.spots.map {
                    TagSpotRow(id: $0.id, lookPhotoID: $0.photoID, x: $0.x, y: $0.y)
                }
                try await client.supabase
                    .from("look_tags")
                    .upsert(spotRows, onConflict: "id", ignoreDuplicates: true)
                    .execute()
                let variantRows = draft.spots.flatMap { spot in
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
        return lookID
    }

    /// Your own looks, newest first, each with its photos in order and its tags.
    ///
    /// **`user_id` is pinned in the query, and RLS is not what makes this
    /// "mine".** `looks` carries TWO select policies — `looks_read_own` and
    /// `looks_public_read` — and Postgres OR's policies for the same command.
    /// An unfiltered select therefore returns your own looks *plus* every
    /// public look you may view, which is a stranger's photo in your own
    /// drafts list.
    ///
    /// Probed, not reasoned: as user A, `select … from looks` returned "A's own
    /// draft + B's public look". `look_photos` and `look_tags` carry the same
    /// pair, but their reads are filtered to ids this call already owns, so the
    /// predicate above is what closes all three (GLO-258).
    ///
    /// Every state comes back, including drafts — that is the point of an
    /// owner-side read, and `MyLook.state` is what lets a caller tell them
    /// apart.
    public func mine() async throws(GlossedError) -> [MyLook] {
        let userID = try await client.requireUserID()
        let looks: [OwnLookRow] = try await run {
            try await client.supabase
                .from("looks")
                .select("id,caption,state,visibility,posted_at,created_at")
                .eq("user_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
        guard !looks.isEmpty else { return [] }
        let lookIDs = looks.map(\.id.uuidString)

        let photos: [OwnPhotoRow] = try await run {
            try await client.supabase
                .from("look_photos")
                .select("id,look_id,r2_key,position")
                .in("look_id", values: lookIDs)
                .order("position")
                .execute()
                .value
        }
        // Tags hang off PHOTOS since 0049, so the id list that scopes them is
        // the photos', not the looks' — and the variant rows hang off the
        // tags in turn. Both reads are filtered to ids this call already
        // owns, which is what keeps GLO-258's rule: the pinned `user_id`
        // above is the scope, and these child fetches inherit it by key.
        let photoIDs = photos.map(\.id.uuidString)
        let tags: [OwnTagRow] = photoIDs.isEmpty ? [] : try await run {
            try await client.supabase
                .from("look_tags")
                .select("id,look_photo_id,x,y")
                .in("look_photo_id", values: photoIDs)
                .execute()
                .value
        }
        let tagIDs = tags.map(\.id.uuidString)
        let variants: [OwnTagVariantRow] = tagIDs.isEmpty ? [] : try await run {
            try await client.supabase
                .from("look_tag_variants")
                .select("look_tag_id,variant_id,position")
                .in("look_tag_id", values: tagIDs)
                .execute()
                .value
        }
        return LooksRepository.assemble(looks: looks, photos: photos, tags: tags, variants: variants)
    }

    /// Publishes a look. One column, and deliberately nothing else.
    ///
    /// **`posted_at` is not sent, and must not be.** A trigger
    /// (`looks_stamp_posted_at`) stamps it when `state` becomes `public` and
    /// clears it if the look ever leaves that state, and the column was revoked
    /// from `authenticated` by 0048 — sending it raises `42501`. The same is
    /// true of `moderation` and `removed_at`.
    ///
    /// **`updated_at` is not sent either**, for the same reason: it is absent
    /// from the update grant. That is a difference from
    /// `RoutinesRepository.rename`, which must ship it by hand — worth stating,
    /// because the two calls otherwise look alike and the wrong instinct here
    /// is a permission error rather than a silent miss.
    ///
    /// **Nothing screens the look.** After this returns, `looks_public_read`
    /// admits it to anyone `can_view` allows, having passed no check. That is
    /// the decision (GLO-238); GLO-26 is the ticket that closes it, and closing
    /// it is one line — drop `'public'` from 0048's with-check.
    ///
    /// A look that is already public is unchanged rather than re-stamped: the
    /// trigger only fires when `state` actually leaves a non-public value, so
    /// calling this twice does not move `posted_at`.
    public func publish(lookID: UUID) async throws(GlossedError) {
        _ = try await client.requireUserID()
        try await run {
            _ = try await client.supabase
                .from("looks")
                .update(StateUpdate(state: .publicState))
                .eq("id", value: lookID.uuidString)
                .execute()
        }
    }

    func run<T>(_ work: () async throws -> T) async throws(GlossedError) -> T {
        do {
            return try await work()
        } catch {
            throw GlossedError.from(error)
        }
    }
}
