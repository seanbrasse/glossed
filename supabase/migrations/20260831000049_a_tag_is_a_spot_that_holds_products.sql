-- 0049 · A tag is a spot on a PHOTO that holds several products. GLO-266.
--
-- 0043's look_tags(look_id, variant_id, x, y) cannot express either half of
-- Sean's spec: there is no photo reference, so "scroll to that photo" has no
-- answer; and the row IS the pairing, so there is no tag identity to hang a
-- second variant on.
--
-- DESTRUCTIVE ON PURPOSE. look_tags holds 0 rows locally and hosted has no
-- looks family at all (list_migrations: 46 entries, no `looks`; pg_class
-- probed directly for all three tables — 0). Probed, not inferred, so there
-- is nothing to back-fill and a drop is honest where a rewrite would pretend.

drop table look_tags;

-- The spot. Coordinates belong to the photo, not the look — that is the whole
-- reshape.
create table look_tags (
    id            uuid primary key default gen_random_uuid(),
    look_photo_id uuid not null references look_photos (id) on delete cascade,
    x             numeric not null check (x between 0 and 1),
    y             numeric not null check (y between 0 and 1),
    created_at    timestamptz not null default now()
);

create index look_tags_photo on look_tags (look_photo_id);

-- The products in that spot.
create table look_tag_variants (
    look_tag_id uuid not null references look_tags (id) on delete cascade,
    variant_id  uuid not null references variants (id),
    -- Order within the one spot's overlay. Deliberately NOT unique: reordering
    -- three products should not need a deferred-constraint dance, and
    -- collection_items sets that precedent. Readers break ties by variant_id.
    position    int not null default 0,
    created_at  timestamptz not null default now(),
    primary key (look_tag_id, variant_id)
);

-- Carried from 0043: "which looks tag this variant" is a taste-engine read.
create index look_tag_variants_variant on look_tag_variants (variant_id);

-- Sean's photo cap is 5 (GLO-266 §3; the composer's constant said 6). With
-- unique (look_id, position) already on the table, bounding `position` bounds
-- the row count, so the cap is a constraint rather than a number in one client.
alter table look_photos add constraint look_photos_cap_5
    check (position between 0 and 4);

-- ---------------------------------------------------------------------------
-- The two predicates, each written ONCE.
--
-- Definer, and not for convenience: a policy expression runs as the invoker, so
-- resolving a tag through look_photos would nest RLS inside RLS — 0021's trap,
-- which resolves a legitimate row to "invisible" and reads like a working
-- privacy feature. These read the parents directly instead.
--
-- look_photo_is_public is 0043's looks_public_read predicate verbatim, state
-- literal included: it tests state = 'public', NOT state <> 'removed', so a
-- state added later fails closed. The test asserts these two agree rather than
-- trusting that they do.
-- ---------------------------------------------------------------------------
create or replace function look_photo_is_own(p_photo uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from look_photos p join looks l on l.id = p.look_id
         where p.id = p_photo and l.user_id = (select auth.uid()));
$$;

create or replace function look_photo_is_public(p_photo uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from look_photos p join looks l on l.id = p.look_id
         where p.id = p_photo
           and l.state = 'public'
           and can_view(l.user_id, 'looks')
           and not viewer_blocked_by(l.user_id));
$$;

-- Both literally delegate, so the logic cannot fork (0020's can_view wrapper is
-- the precedent). A tag id that does not exist yields null, and the delegate
-- answers false — fail closed.
create or replace function look_tag_is_own(p_tag uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select look_photo_is_own((select look_photo_id from look_tags where id = p_tag));
$$;

create or replace function look_tag_is_public(p_tag uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select look_photo_is_public((select look_photo_id from look_tags where id = p_tag));
$$;

alter table look_tags         enable row level security;
alter table look_tag_variants enable row level security;

-- Split, never `for all` — a broad owner policy OR's with the gated ones and
-- defeats them (0026's minor-bypass lesson, carried by 0043).
create policy look_tags_own on look_tags for select
    to authenticated
    using (look_photo_is_own(look_photo_id));

-- 0043 gated look_photos INSERT on can_post_look() but not look_tags, and that
-- asymmetry is now closed by construction rather than by a second check: a tag
-- cannot exist without a photo, and a photo cannot exist without that gate.
create policy look_tags_insert_own on look_tags for insert
    to authenticated
    with check (look_photo_is_own(look_photo_id));

create policy look_tags_delete_own on look_tags for delete
    to authenticated
    using (look_photo_is_own(look_photo_id));

create policy look_tags_public_read on look_tags for select
    to authenticated
    using (look_photo_is_public(look_photo_id));

create policy look_tag_variants_own on look_tag_variants for select
    to authenticated
    using (look_tag_is_own(look_tag_id));

create policy look_tag_variants_insert_own on look_tag_variants for insert
    to authenticated
    with check (look_tag_is_own(look_tag_id));

create policy look_tag_variants_delete_own on look_tag_variants for delete
    to authenticated
    using (look_tag_is_own(look_tag_id));

create policy look_tag_variants_public_read on look_tag_variants for select
    to authenticated
    using (look_tag_is_public(look_tag_id));

-- No UPDATE policy on either table, carried from 0043: the composer writes tag
-- sets, so moving a pin is a delete and an insert.

-- Supabase's default privileges hand new tables to anon and authenticated —
-- revoke from the ROLES, not from `public`, or the revoke is a no-op that reads
-- like protection (0024, 0027). look_tags was dropped above, so its 0043
-- revoke went with it.
revoke all on table look_tags, look_tag_variants from anon;

revoke execute on function look_photo_is_own(uuid), look_photo_is_public(uuid),
    look_tag_is_own(uuid), look_tag_is_public(uuid) from public, anon, authenticated;
grant execute on function look_photo_is_own(uuid), look_photo_is_public(uuid),
    look_tag_is_own(uuid), look_tag_is_public(uuid) to authenticated;

comment on table look_tags is
    'A spot on ONE photo, holding several products via look_tag_variants. GLO-266 — 0043 keyed tags to the look and to a single variant, which could express neither.';

comment on policy look_tags_public_read on look_tags is
    'Rides the photo''s parent look: state = ''public'', not state <> ''removed'', so a future state fails closed. A tag never widens what a variant''s viewer could already see.';

comment on constraint look_photos_cap_5 on look_photos is
    'Sean''s 5-photo cap (GLO-266). unique (look_id, position) + a bounded position is the cap; it holds against any client, dense positions or not.';
