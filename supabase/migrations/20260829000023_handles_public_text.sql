-- 0023 · Handles, moderated public text, and badge opt-ins. GLO-120.
-- docs/tech/02 §3.1, §3.2, §3.4.
--
-- The identity layer. Nothing here is visible to another user yet — GLO-121's
-- public_profile() RPC is what reads it. This migration only establishes that
-- the data exists, is unique, is moderated, and defaults to private.

create type moderation_state as enum ('pending', 'approved', 'rejected');
create type public_text_kind as enum ('bio', 'handle', 'collection_title', 'routine_title', 'linked_social');

-- ---------------------------------------------------------------------------
-- Handles. Claimed at FIRST PUBLISH, not at signup — V1 never needed one.
--
-- There is no handle-CHANGE flow in 1.5, which is precisely why there is no
-- release/cooldown table: you cannot free a handle, so nobody can snipe one.
-- If a change flow is ever added, the cooldown table has to come with it.
-- ---------------------------------------------------------------------------
create table handles (
    user_id    uuid primary key references auth.users (id) on delete cascade,
    handle     text not null unique,
    claimed_at timestamptz not null default now(),
    constraint handle_shape check (handle ~ '^[a-z0-9][a-z0-9_.]{1,29}$' and handle !~ '\.\.')
);

-- Seeded with every top-level path segment GLO-30's share scheme will ever
-- mint, plus the safety set. Reserving the routes BEFORE the URL scheme ships
-- is cheap; discovering that @c collides with /c/<slug> after the first card is
-- in the wild is not.
create table reserved_handles (
    handle text primary key,
    reason text not null check (reason in ('route', 'safety', 'brand'))
);

insert into reserved_handles (handle, reason) values
    ('c','route'), ('p','route'), ('u','route'), ('v','route'), ('s','route'),
    ('api','route'), ('app','route'), ('www','route'), ('rpc','route'),
    ('auth','route'), ('login','route'), ('signup','route'), ('settings','route'),
    ('admin','route'), ('support','route'), ('help','route'), ('about','route'),
    ('terms','route'), ('privacy','route'), ('legal','route'), ('security','route'),
    ('glossed','safety'), ('official','safety'), ('team','safety'), ('staff','safety'),
    ('moderator','safety'), ('mod','safety'), ('admin_','safety'), ('root','safety'),
    ('null','safety'), ('undefined','safety'), ('me','safety'), ('you','safety');

-- ---------------------------------------------------------------------------
-- public_texts — ONE table, not four.
--
-- Every user-authored string another user can see lives here. Sprinkling a
-- moderation_state column across profiles, handles, collections and routines
-- guarantees the fifth one gets forgotten.
--
-- THE RENDER RULE this table exists for: a public surface reads only
-- state = 'approved'. A pending edit renders the previously approved body, or
-- nothing — never the pending text. That closes the window between the write
-- and the model's answer, which is exactly where the naive design leaks.
-- ---------------------------------------------------------------------------
create table public_texts (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users (id) on delete cascade,
    kind       public_text_kind not null,
    subject_id uuid,                       -- collection/routine id; null for bio and handle
    body       text not null,
    state      moderation_state not null default 'pending',
    model      text,
    verdict    jsonb,
    decided_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    -- NULLS NOT DISTINCT so one bio per user, not one per null subject_id.
    -- PG15+; config.toml pins 17.
    constraint public_texts_one_per_subject unique nulls not distinct (user_id, kind, subject_id)
);
create index public_texts_pending on public_texts (state) where state = 'pending';

-- ---------------------------------------------------------------------------
-- profile_badges. Regulated data may be published by the user's own explicit
-- act — that is what "hideable badges" means. All three default FALSE, and
-- they remain the only path by which skin type, anchor and hair pattern reach
-- another human. They still never reach an event prop
-- (events_no_regulated_props, 0021).
-- ---------------------------------------------------------------------------
create table profile_badges (
    user_id           uuid primary key references auth.users (id) on delete cascade,
    show_skin_type    boolean not null default false,
    show_anchor       boolean not null default false,
    show_hair_pattern boolean not null default false
);

-- ---------------------------------------------------------------------------
-- claim_handle. The only path to a handle: there is deliberately no insert
-- policy on `handles`.
--
-- The unique index does the race. The client renders 23505 as "taken", which
-- is why the availability check is advisory UI and the insert is the truth.
-- ---------------------------------------------------------------------------
create or replace function claim_handle(p_handle text)
returns text language plpgsql security definer set search_path = public as $$
declare
    v_user uuid := (select auth.uid());
    v_h    text := lower(trim(p_handle));
begin
    if v_user is null then
        raise exception 'sign in to claim a handle' using errcode = 'insufficient_privilege';
    end if;
    -- A handle IS the public identity; there is nothing for a locked-private
    -- account to claim.
    if is_minor_user(v_user) then
        raise exception 'handles are a public identity' using errcode = 'check_violation';
    end if;
    if exists (select 1 from reserved_handles where handle = v_h) then
        raise exception 'handle reserved' using errcode = 'check_violation';
    end if;
    -- Impersonation rides data we already have: 497 brands and growing, so this
    -- check strengthens for free as the catalog grows.
    if exists (select 1 from brands where normalized_name = v_h) then
        raise exception 'handle matches a brand name' using errcode = 'check_violation';
    end if;

    insert into handles (user_id, handle) values (v_user, v_h);

    -- The handle is moderated text like any other. It lands `pending`; nothing
    -- public renders it until a reviewer or the model approves it (GLO-141).
    insert into public_texts (user_id, kind, subject_id, body)
    values (v_user, 'handle', null, v_h);

    return v_h;
end $$;

-- Answers only "is this handle free", which a caller learns by trying anyway.
-- Same doctrine as can_follow: the client-reachable surface reveals nothing it
-- could not already determine.
create or replace function handle_available(p_handle text)
returns boolean language sql stable security definer set search_path = public as $$
    select p_handle ~ '^[a-z0-9][a-z0-9_.]{1,29}$'
       and p_handle !~ '\.\.'
       and not exists (select 1 from handles where handle = lower(trim(p_handle)))
       and not exists (select 1 from reserved_handles where handle = lower(trim(p_handle)))
       and not exists (select 1 from brands where normalized_name = lower(trim(p_handle)));
$$;

-- Writing public text always lands `pending`. The client cannot set `state` —
-- there is no update policy for it — so "approved" is never self-declared.
create or replace function set_public_text(p_kind public_text_kind, p_subject uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
    v_user uuid := (select auth.uid());
    v_id   uuid;
begin
    if v_user is null then
        raise exception 'sign in first' using errcode = 'insufficient_privilege';
    end if;
    insert into public_texts (user_id, kind, subject_id, body)
    values (v_user, p_kind, p_subject, p_body)
    on conflict (user_id, kind, subject_id) do update
        set body = excluded.body,
            state = 'pending',      -- an edit re-enters review, always
            model = null, verdict = null, decided_at = null,
            updated_at = now()
    returning id into v_id;
    return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- RLS. Everything here is owner-only for now; GLO-121's public_profile() RPC
-- is what exposes any of it, as a projection rather than relaxed policy.
-- ---------------------------------------------------------------------------
alter table handles          enable row level security;
alter table reserved_handles enable row level security;
alter table public_texts     enable row level security;
alter table profile_badges   enable row level security;

-- Read your own handle. No insert policy: claim_handle is the only path.
create policy handles_read_own on handles for select
    to authenticated
    using (user_id = (select auth.uid()));

-- reserved_handles gets NO policy at all. RLS on with zero policies means
-- deny-all to anon/authenticated; only definer functions and service_role read
-- it. Enumerating the reserved list is a gift to squatters.

-- Read your own text. No write policies: set_public_text is the only path, so
-- `state` cannot be self-declared.
create policy public_texts_read_own on public_texts for select
    to authenticated
    using (user_id = (select auth.uid()));

create policy profile_badges_own on profile_badges for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Grants. Full intended ACL stated per object: revoke from everyone, then
-- grant exactly the roles that need it. A grant does not imply a revoke, and
-- under Supabase's default privileges silence is a grant (0020/0022's lesson).
-- ---------------------------------------------------------------------------
revoke execute on function claim_handle(text)                                  from public, anon, authenticated;
revoke execute on function handle_available(text)                              from public, anon, authenticated;
revoke execute on function set_public_text(public_text_kind, uuid, text)       from public, anon, authenticated;

grant execute on function claim_handle(text)                            to authenticated;
grant execute on function handle_available(text)                        to authenticated;
grant execute on function set_public_text(public_text_kind, uuid, text) to authenticated;

comment on table public_texts is
    'Every user-authored string another user can see. A public surface reads only state = ''approved''; a pending edit renders the previously approved body, never the pending one. GLO-120, docs/tech/02 §3.2.';
