-- 0050 · A look links a routine or a collection. GLO-263, GLO-218.
--
-- TYPED TABLES, NOT ONE POLYMORPHIC TABLE, and the reason is visible three
-- statements below: a routine resolves through can_view(owner,'routines') —
-- privacy_scopes — while a collection resolves through collection_is_visible(),
-- because a collection carries its OWN visibility column (0021). The two kinds
-- do not differ by a column, they differ by which FUNCTION answers for them. A
-- polymorphic table would have to branch on a kind discriminator to pick one,
-- with an FK Postgres cannot enforce, which is the bet GLO-238 and GLO-258 both
-- lost this week.

create table look_routines (
    look_id    uuid not null references looks (id) on delete cascade,
    routine_id uuid not null references routines (id) on delete cascade,
    position   int not null default 0,
    created_at timestamptz not null default now(),
    primary key (look_id, routine_id)
);

create table look_collections (
    look_id       uuid not null references looks (id) on delete cascade,
    collection_id uuid not null references collections (id) on delete cascade,
    position      int not null default 0,
    created_at    timestamptz not null default now(),
    primary key (look_id, collection_id)
);

-- ---------------------------------------------------------------------------
-- The look-level predicates. Definer because a policy expression runs as the
-- invoker, and resolving a parent through another RLS'd table nests RLS inside
-- RLS — 0021's trap, which resolves a legitimate row to "invisible" and reads
-- exactly like a working privacy feature.
-- ---------------------------------------------------------------------------
create or replace function look_is_own(p_look uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (select 1 from looks
                    where id = p_look and user_id = (select auth.uid()));
$$;

-- 0043's looks_public_read predicate verbatim, state literal included: it tests
-- state = 'public', NOT state <> 'removed', so a state added later fails closed.
create or replace function look_is_public(p_look uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from looks l
         where l.id = p_look
           and l.state = 'public'
           and can_view(l.user_id, 'looks')
           and not viewer_blocked_by(l.user_id));
$$;

-- The routines counterpart to 0021's collection_is_visible, and deliberately
-- the same shape: browse_routines resolves a routine's visibility as
-- `deleted_at is null and can_view(owner,'routines')`, so this does too.
create or replace function routine_is_visible(p_routine uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (select 1 from routines r
                    where r.id = p_routine
                      and r.deleted_at is null
                      and can_view(r.user_id, 'routines'));
$$;

alter table look_routines    enable row level security;
alter table look_collections enable row level security;

create policy look_routines_own on look_routines for select
    to authenticated
    using (look_is_own(look_id));

-- Own-only, and the direction of the asymmetry is the point: loosening this to
-- "any routine you may view" is a one-line alter, tightening it after rows
-- exist is not. Whether a look may link SOMEONE ELSE'S routine is Sean's call,
-- not a default to back into. No definer needed on the routines half — the
-- owner's own routines_own policy already answers it, so there is no nesting.
create policy look_routines_insert_own on look_routines for insert
    to authenticated
    with check (look_is_own(look_id) and exists (
        select 1 from routines r
         where r.id = routine_id and r.user_id = (select auth.uid())
           and r.deleted_at is null));

create policy look_routines_delete_own on look_routines for delete
    to authenticated
    using (look_is_own(look_id));

-- THE PRIVACY TRAP, and it is the whole ticket. A link leaks the EXISTENCE of
-- the thing it links: a public look that links an only_you routine must render
-- nothing — not the name, not a placeholder, not a greyed row. Both halves are
-- required and both fail closed, so the link is visible only where the look AND
-- the routine independently are.
create policy look_routines_public_read on look_routines for select
    to authenticated
    using (look_is_public(look_id) and routine_is_visible(routine_id));

create policy look_collections_own on look_collections for select
    to authenticated
    using (look_is_own(look_id));

create policy look_collections_insert_own on look_collections for insert
    to authenticated
    with check (look_is_own(look_id) and exists (
        select 1 from collections c
         where c.id = collection_id and c.user_id = (select auth.uid())
           and c.deleted_at is null));

create policy look_collections_delete_own on look_collections for delete
    to authenticated
    using (look_is_own(look_id));

-- collection_is_visible is 0021's, reused rather than restated — a second
-- spelling of a visibility rule is the drift this ticket exists to avoid.
create policy look_collections_public_read on look_collections for select
    to authenticated
    using (look_is_public(look_id) and collection_is_visible(collection_id));

-- No UPDATE policy on either table: a reorder is a delete and an insert, as on
-- look_tags and look_photos.

-- Revoke from the ROLES, not from `public`, or the revoke is a no-op that reads
-- like protection (0024, 0027).
revoke all on table look_routines, look_collections from anon;

revoke execute on function look_is_own(uuid), look_is_public(uuid),
    routine_is_visible(uuid) from public, anon, authenticated;
grant execute on function look_is_own(uuid), look_is_public(uuid),
    routine_is_visible(uuid) to authenticated;

comment on policy look_routines_public_read on look_routines is
    'BOTH halves, both fail closed: a link is visible only where the look AND the routine independently are. A public look linking an only_you routine renders NOTHING (GLO-263).';

comment on policy look_collections_public_read on look_collections is
    'Same rule as look_routines_public_read, through collection_is_visible (0021) because a collection carries its own visibility column — which is why these are typed tables and not one polymorphic one.';
