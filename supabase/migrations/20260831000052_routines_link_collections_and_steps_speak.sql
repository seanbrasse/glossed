-- 0052 · Routines link collections, and a step can say what you do with it.
-- Sean's ask, Aug 31: "build out the ability to link looks, collections, and
-- routines together" — 0050 built the look→routine and look→collection pairs,
-- this adds the third — and "routines can also have notes added per step, for
-- users to add details on what they're doing with that product/step."
--
-- Everything here follows 0050's decisions rather than remaking them: typed
-- table (the two kinds differ by which FUNCTION answers for them, not by a
-- column), own-only writes (loosening later is one line, tightening after
-- rows exist is not), and the privacy trap closed on BOTH halves — a link is
-- visible only where the routine AND the collection independently are.

-- ---------------------------------------------------------------------------
-- The step's note.
-- ---------------------------------------------------------------------------
-- On `routine_steps` itself, not a side table: a note belongs to the step the
-- way `position` does, and it dies with the step (the cascade already there).
--
-- Bounded in the schema, not just the client: a "note" that admits a novel is
-- a caption field wearing the wrong name, and every client-side cap in this
-- repo (captionCap, the handle rules) has a server twin for the same reason.
--
-- MODERATION: none, and stated. Step notes are user-authored free text that
-- reaches strangers when the routine's scope opens (routine_steps_public rides
-- the routine's visibility). Text moderation is parked project-wide (GLO-31
-- carries it; 0045 records the parking); step notes join bios and collection
-- titles in that queue rather than getting a private rule here.
alter table routine_steps add column note text
    constraint routine_steps_note_length check (char_length(note) <= 500);

comment on column routine_steps.note is
    'The owner''s own words on what they do with this product in this step (GLO-263 family, Sean''s Aug 31 ask). Reaches whoever the ROUTINE reaches — no scope of its own. Unmoderated pending GLO-31, like every user text.';

-- ---------------------------------------------------------------------------
-- The third pair: routine → collection.
-- ---------------------------------------------------------------------------
create table routine_collections (
    routine_id    uuid not null references routines (id) on delete cascade,
    collection_id uuid not null references collections (id) on delete cascade,
    position      int not null default 0,
    created_at    timestamptz not null default now(),
    primary key (routine_id, collection_id)
);

alter table routine_collections enable row level security;

-- The owner of the ROUTINE owns the link — 0050's rule carried over: the link
-- hangs off the thing that is being annotated, and its owner decides.
--
-- The own-check is a plain invoker exists() on purpose (no definer): only the
-- caller's OWN rows are needed, `routines_own` answers that without nesting,
-- and 0050's insert checks set the precedent.
create policy routine_collections_own on routine_collections for select
    to authenticated
    using (exists (select 1 from routines r
                    where r.id = routine_id
                      and r.user_id = (select auth.uid())));

create policy routine_collections_insert_own on routine_collections for insert
    to authenticated
    with check (
        exists (select 1 from routines r
                 where r.id = routine_id
                   and r.user_id = (select auth.uid())
                   and r.deleted_at is null)
        and exists (select 1 from collections c
                     where c.id = collection_id
                       and c.user_id = (select auth.uid())
                       and c.deleted_at is null));

create policy routine_collections_delete_own on routine_collections for delete
    to authenticated
    using (exists (select 1 from routines r
                    where r.id = routine_id
                      and r.user_id = (select auth.uid())));

-- THE PRIVACY TRAP, 0050's words because it is 0050's rule: a link leaks the
-- EXISTENCE of the thing it links. Both halves are required and both fail
-- closed, so the link is visible only where the routine AND the collection
-- independently are. Both predicates already exist — routine_is_visible is
-- 0050's, collection_is_visible is 0021's — reused rather than restated,
-- because a second spelling of a visibility rule is drift.
create policy routine_collections_public_read on routine_collections for select
    to authenticated
    using (routine_is_visible(routine_id) and collection_is_visible(collection_id));

-- No UPDATE policy: a reorder is a delete and an insert, as on look_routines,
-- look_tags and look_photos.

-- Revoke from the ROLES, not from `public` (0024, 0027).
revoke all on table routine_collections from anon;

comment on policy routine_collections_public_read on routine_collections is
    'BOTH halves, both fail closed (0050''s rule): a public routine linking an only_you collection renders NOTHING to a stranger — no name, no row, no count.';
