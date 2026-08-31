-- 0054 — batch 2 of Sean's Aug 31 rulings (tracked on GLO-272; the Linear
-- workspace is at its issue cap, recorded there in a comment).
--
-- Two ideas share the migration because the slot is one PR project-wide:
-- collections learn to describe themselves, and a look commits to at most
-- ONE routine and ONE collection.

-- ---------------------------------------------------------------------------
-- The collection's description.
-- ---------------------------------------------------------------------------
-- On `collections` itself, `routine_steps.note`'s reasoning verbatim: it
-- belongs to the row and dies with it. Bounded in the schema because every
-- client-side cap here has a server twin — 500, the note's own number, since
-- both are "the owner's words about a thing," not an essay field.
--
-- MODERATION: none, and stated — the 0052 queue (GLO-31 carries text
-- moderation project-wide; 0045 records the parking). A description reaches
-- whoever the COLLECTION reaches: `collections_public` rides
-- `collection_is_visible`, and this column rides the row.
--
-- No new grant needed: collections' INSERT and UPDATE privileges are
-- table-wide for `authenticated` (probed — information_schema.column_privileges
-- lists every column), so the new column rides along; RLS still pins rows to
-- their owner.
alter table collections add column description text
    constraint collections_description_length check (char_length(description) <= 500);

comment on column collections.description is
    'The owner''s own words on what this collection is (Sean, Aug 31 batch 2). Reaches whoever the COLLECTION reaches — no scope of its own. Unmoderated pending GLO-31, like every user text.';

-- ---------------------------------------------------------------------------
-- A look commits: one routine, one collection.
-- ---------------------------------------------------------------------------
-- Sean's cardinality ruling, verbatim: "A routine can have several
-- collections or looks linked to it. A collection can have several looks and
-- routines linked to it. A look can have ONE collection, and ONE routine
-- linked to it."
--
-- The asymmetry is real, not a typo: from the routine's or collection's side
-- nothing changes (many looks may point at the same routine — that is the
-- routine being popular, and these indexes do not touch it). What tightens
-- is the LOOK's side of both pairs: one row per look in each table.
--
-- UNIQUE INDEXES, not new primary keys: the composite PKs from 0050 stay
-- (they are what upserts conflict on), and a partial or filtered form is not
-- needed — the tables have no soft delete, a row either exists or does not.
--
-- No backfill dilemma: probed before writing — zero looks hold more than one
-- routine or more than one collection, so these apply to the data as it
-- stands. Had there been extras, picking a survivor would have been a
-- product decision, not a migration's.
--
-- The write path this changes: `link()` upserts with `ignoreDuplicates` on
-- the composite key. A SECOND routine for a look now violates this index
-- instead of inserting — a 23505 the client must treat as "replace, don't
-- add": delete the old link, insert the new. The UI's pickers become
-- single-choice for looks in the same batch, so the error is the backstop,
-- not the flow.
create unique index look_routines_one_per_look on look_routines (look_id);
create unique index look_collections_one_per_look on look_collections (look_id);

comment on index look_routines_one_per_look is
    'Sean''s Aug 31 cardinality ruling: a look links at most one routine. The routine side stays many.';
comment on index look_collections_one_per_look is
    'Sean''s Aug 31 cardinality ruling: a look links at most one collection. The collection side stays many.';

-- ---------------------------------------------------------------------------
-- A look photo's bytes can be swapped (Sean, Aug 31 evening).
-- ---------------------------------------------------------------------------
-- "clicking on it should open the photo up and then allow the user to swap
-- it … This is how the looks should work too." This SUPERSEDES the morning's
-- images-immutable ruling, and the write is shaped to keep what mattered
-- about it: the photo ROW survives — same id, same position, same tags
-- pinned to it — and only `r2_key` moves. A swap is a re-shoot of the same
-- slot, not a new slot; the old object orphans for the sweep, cutouts'
-- lifecycle.
--
-- UPDATE was deliberately absent here (0043: insert/delete/select only), so
-- both halves are new: the policy admits the look's owner, and the grant
-- admits ONLY the r2_key column — position stays delete+insert (0049's
-- "moving a pin" rule is untouched), and look_id/id cannot be repointed.
create policy look_photos_update_own on look_photos for update
    using (
        exists (
            select 1 from looks l
            where l.id = look_photos.look_id and l.user_id = (select auth.uid())
        )
    )
    with check (
        exists (
            select 1 from looks l
            where l.id = look_photos.look_id and l.user_id = (select auth.uid())
        )
    );

grant update (r2_key) on look_photos to authenticated;

comment on policy look_photos_update_own on look_photos is
    'The photo-swap ruling (Sean, Aug 31 evening): the owner re-points a photo''s bytes; the row, its position and its tags stay put. Only r2_key is granted.';
