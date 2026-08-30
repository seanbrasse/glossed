-- 0043 · Looks — the feed's photo posts. GLO-197 (GLO-32 slice 1/4).
-- docs/tech/03 §1, delta 11 (the feed is V1), delta 15 (one stream).
-- Gates copied from 0026's shape: definer wrappers, split policies,
-- explicit anon revokes.

create type look_state as enum ('draft', 'pending_review', 'public', 'removed');

create table looks (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users (id) on delete cascade,
    caption    text check (char_length(caption) <= 2200),
    -- Nothing moves a row to 'public' until cloud image moderation exists
    -- (GLO-26). Until then looks are owner-visible drafts, and the composer's
    -- copy says so (GLO-189: no review language before a reviewer exists).
    state      look_state not null default 'draft',
    moderation jsonb,
    posted_at  timestamptz,
    removed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- The feed reads public-recent (fan-out on read, tech/03 §2); the composer
-- reads own.
create index looks_public_recent on looks (posted_at desc) where state = 'public';
create index looks_user on looks (user_id);

create table look_photos (
    id         uuid primary key default gen_random_uuid(),
    look_id    uuid not null references looks (id) on delete cascade,
    r2_key     text not null,
    position   int not null default 0,
    created_at timestamptz not null default now(),
    unique (look_id, position)
);

create table look_tags (
    look_id    uuid not null references looks (id) on delete cascade,
    variant_id uuid not null references variants (id),
    -- Pin position, normalized to the photo — tags survive any render size.
    x          numeric not null check (x between 0 and 1),
    y          numeric not null check (y between 0 and 1),
    created_at timestamptz not null default now(),
    primary key (look_id, variant_id)
);

create index look_tags_variant on look_tags (variant_id);

-- May the CALLER post a look at all? Definer, because is_minor_user is
-- revoked from clients (0020) and a policy executes as the invoker.
-- Minors never post photos — a launch requirement (delta 11), not a
-- preference.
create or replace function can_post_look()
returns boolean language sql stable security definer set search_path = public as $$
    select (select auth.uid()) is not null
       and not is_minor_user((select auth.uid()));
$$;

alter table looks       enable row level security;
alter table look_photos enable row level security;
alter table look_tags   enable row level security;

-- Split, not `for all` — permissive policies OR together, and a broad owner
-- policy would defeat the gated insert below (0026's minor-bypass lesson).
create policy looks_read_own on looks for select
    to authenticated
    using (user_id = (select auth.uid()));

create policy looks_update_own on looks for update
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

create policy looks_delete_own on looks for delete
    to authenticated
    using (user_id = (select auth.uid()));

create policy looks_insert_own on looks for insert
    to authenticated
    with check (user_id = (select auth.uid()) and can_post_look());

-- Tests state = 'public', NOT state <> 'removed' — a state added later fails
-- closed (0026's rule). First reader of the `looks` scope (0020): a public
-- look is a per-act publish, but the profile scope still governs browsing,
-- and a block severs regardless.
create policy looks_public_read on looks for select
    to authenticated
    using (state = 'public'
       and can_view(user_id, 'looks')
       and not viewer_blocked_by(user_id));

-- Children answer through the parent; photo INSERT re-checks can_post_look()
-- directly so the minor gate holds even against a pre-existing draft row.
create policy look_photos_own on look_photos for select
    to authenticated
    using (exists (select 1 from looks l
                    where l.id = look_id and l.user_id = (select auth.uid())));

create policy look_photos_insert_own on look_photos for insert
    to authenticated
    with check (can_post_look() and exists (
        select 1 from looks l
         where l.id = look_id and l.user_id = (select auth.uid())));

create policy look_photos_delete_own on look_photos for delete
    to authenticated
    using (exists (select 1 from looks l
                    where l.id = look_id and l.user_id = (select auth.uid())));

create policy look_photos_public_read on look_photos for select
    to authenticated
    using (exists (select 1 from looks l
                    where l.id = look_id
                      and l.state = 'public'
                      and can_view(l.user_id, 'looks')
                      and not viewer_blocked_by(l.user_id)));

create policy look_tags_own on look_tags for select
    to authenticated
    using (exists (select 1 from looks l
                    where l.id = look_id and l.user_id = (select auth.uid())));

create policy look_tags_write_own on look_tags for insert
    to authenticated
    with check (exists (select 1 from looks l
                         where l.id = look_id and l.user_id = (select auth.uid())));

create policy look_tags_delete_own on look_tags for delete
    to authenticated
    using (exists (select 1 from looks l
                    where l.id = look_id and l.user_id = (select auth.uid())));

create policy look_tags_public_read on look_tags for select
    to authenticated
    using (exists (select 1 from looks l
                    where l.id = look_id
                      and l.state = 'public'
                      and can_view(l.user_id, 'looks')
                      and not viewer_blocked_by(l.user_id)));

-- Supabase default privileges hand new tables to anon and authenticated —
-- revoke from the ROLES, not from `public`, or the revoke is a no-op that
-- reads like protection (0024, 0027).
revoke all on table looks, look_photos, look_tags from anon;

revoke execute on function can_post_look() from public, anon, authenticated;
grant execute on function can_post_look() to authenticated;

comment on policy looks_public_read on looks is
    'Tests state = ''public'', not state <> ''removed'' — a future state fails closed. First reader of privacy_scopes.looks (0020).';
