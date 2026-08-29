-- 0020 · Privacy core: scopes, the graph, and the one visibility function.
-- GLO-115. docs/tech/02 §1.2–§1.6.
--
-- THE PHASE-1.5 GATE. Every 1.5 read policy is written
-- `owner = auth.uid() OR can_view(owner, <surface>)`, so a migration that
-- creates one before this file has applied fails at CREATE POLICY. The
-- ordering is enforced by Postgres, not by discipline.
--
-- This migration is purely ADDITIVE. It modifies no Phase-1 policy and no
-- Phase-1 table. If Phase 1's 125 assertions move at all, something here is
-- wrong.
--
-- Creation order below is dependency-first and deliberate: a `language sql`
-- body is parsed AND resolved at CREATE FUNCTION time (check_function_bodies
-- defaults to on), while a `language plpgsql` body is not. can_view's 3-arg
-- body is plpgsql and *could* forward-reference its helpers; the 2-arg wrapper
-- is sql and could not. Writing the file dependency-first costs nothing and
-- removes the question.

create type scope_enum as enum ('only_you', 'friends', 'public');
create type visibility_surface as enum ('shelf', 'rankings', 'routines', 'looks');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table privacy_scopes (
    user_id      uuid primary key references auth.users (id) on delete cascade,
    shelf        scope_enum not null default 'only_you',
    rankings     scope_enum not null default 'only_you',
    routines     scope_enum not null default 'only_you',
    looks        scope_enum not null default 'only_you', -- inert until Phase 2; shipped now so Phase 2 inherits a tested column
    discoverable boolean not null default false,         -- surfaced in suggestions at all; NOT part of can_view (§1.3)
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

-- Follow is not mutual. `friends` IS (§1.3, Sean's ruling Aug 29) — the
-- permissive reading lets a stranger self-serve into a friends-scoped shelf by
-- tapping follow, which makes `friends` a slower spelling of `public`.
create table follows (
    follower_id uuid not null references auth.users (id) on delete cascade,
    followed_id uuid not null references auth.users (id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (follower_id, followed_id),
    constraint follows_not_self check (follower_id <> followed_id)
);
create index follows_followed on follows (followed_id);

-- The blocked party must never be able to read this table, which is why
-- is_blocked() is security definer: can_view has to see rows the viewer cannot.
create table blocks (
    user_id    uuid not null references auth.users (id) on delete cascade, -- the blocker
    blocked_id uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, blocked_id),
    constraint blocks_not_self check (user_id <> blocked_id)
);
create index blocks_blocked on blocks (blocked_id);

-- Mute suppresses someone from YOUR suggestions and trending rows. It changes
-- no visibility in either direction — that is the whole difference from block.
create table mutes (
    user_id    uuid not null references auth.users (id) on delete cascade,
    muted_id   uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, muted_id),
    constraint mutes_not_self check (user_id <> muted_id)
);

-- ---------------------------------------------------------------------------
-- Helpers, dependency-first
-- ---------------------------------------------------------------------------

-- Conservative by up to one month, deliberately (domain.md §6): certainly-18
-- starts on the 1st of the month after the 18th birthday could have occurred.
create or replace function is_minor(p_birth char(7), p_on date default current_date)
returns boolean language sql immutable parallel safe set search_path = public as $$
    select p_on < (to_date(p_birth || '-01', 'YYYY-MM-DD') + interval '18 years 1 month')::date;
$$;

-- No profile row is treated as a minor. Default-deny on the age gate too.
-- NOTE: user_facts.minor (0011) is a scheduled analytics snapshot and is NOT
-- the authority here — a stale `false` there would be a disclosure.
create or replace function is_minor_user(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select coalesce((select is_minor(p.birth_year_month) from profiles p where p.user_id = p_user), true);
$$;

create or replace function is_blocked(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select p_a is not null and p_b is not null and exists (
        select 1 from blocks
         where (user_id = p_a and blocked_id = p_b)
            or (user_id = p_b and blocked_id = p_a));
$$;

create or replace function is_mutual_follow(p_a uuid, p_b uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select p_a is not null and p_b is not null
       and exists (select 1 from follows where follower_id = p_a and followed_id = p_b)
       and exists (select 1 from follows where follower_id = p_b and followed_id = p_a);
$$;

-- The one visibility function. Order of evaluation is load-bearing and is
-- asserted step by step in the viewer-pair grids (GLO-117 / GLO-118):
--   owner short-circuit → block → minor lock → scope → relationship.
-- Blocks beat `public`. The minor lock beats everything except the owner.
create or replace function can_view(p_viewer uuid, p_owner uuid, p_surface visibility_surface)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
    v_scope scope_enum;
begin
    if p_owner is null then return false; end if;
    if p_viewer is not null and p_viewer = p_owner then return true; end if;
    if is_blocked(p_viewer, p_owner) then return false; end if;
    if is_minor_user(p_owner) then return false; end if;

    select case p_surface
               when 'shelf'    then s.shelf
               when 'rankings' then s.rankings
               when 'routines' then s.routines
               when 'looks'    then s.looks
           end
      into v_scope
      from privacy_scopes s
     where s.user_id = p_owner;

    -- No row is not a missing answer. No row is `only_you`.
    if v_scope is null or v_scope = 'only_you' then return false; end if;
    if v_scope = 'public' then return true; end if;
    return is_mutual_follow(p_viewer, p_owner); -- v_scope = 'friends'
end $$;

-- The RLS-facing wrapper. Literally delegates, so the logic cannot fork.
create or replace function can_view(p_owner uuid, p_surface visibility_surface)
returns boolean language sql stable security definer set search_path = public as $$
    select can_view((select auth.uid()), p_owner, p_surface);
$$;

-- May the CALLER follow this person? Same doctrine as can_view's 2-arg wrapper:
-- the client-reachable surface answers only about auth.uid(), never about an
-- arbitrary pair.
--
-- This exists because RLS policy expressions execute as the INVOKING user, so
-- every function a policy calls must be executable by that user. The insert
-- policy below needs is_blocked() and is_minor_user(), both of which are
-- revoked from clients on purpose — is_blocked would expose arbitrary block
-- relationships and is_minor_user would expose anyone's minor status. Wrapping
-- them in a definer function keeps the policy working while the client can only
-- ask a question it could answer anyway by trying.
create or replace function can_follow(p_target uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select p_target is not null
       and p_target <> (select auth.uid())
       and not is_blocked((select auth.uid()), p_target)
       and not is_minor_user(p_target);
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- The polite half of the minors lock. The load-bearing half is the read side:
-- can_view returns false for a minor owner BEFORE it looks at the scope row, so
-- a bad write, a service_role write, or a future migration cannot leak.
create or replace function lock_minor_scopes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    if is_minor_user(new.user_id) then
        if new.shelf <> 'only_you' or new.rankings <> 'only_you'
           or new.routines <> 'only_you' or new.looks <> 'only_you' or new.discoverable then
            raise exception 'minors are private by construction' using errcode = 'check_violation';
        end if;
    end if;
    return new;
end $$;

create trigger privacy_scopes_minor_lock before insert or update on privacy_scopes
    for each row execute function lock_minor_scopes();

-- A block that leaves a follow edge standing is a bug that reads as a working
-- feature. Severing the graph is part of blocking, not a follow-up action.
create or replace function sever_follows_on_block() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    delete from follows
     where (follower_id = new.user_id and followed_id = new.blocked_id)
        or (follower_id = new.blocked_id and followed_id = new.user_id);
    return new;
end $$;

create trigger blocks_sever_follows after insert on blocks
    for each row execute function sever_follows_on_block();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table privacy_scopes enable row level security;
alter table follows        enable row level security;
alter table blocks         enable row level security;
alter table mutes          enable row level security;

create policy privacy_scopes_own on privacy_scopes for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

-- You see your own edges, and only your own. Follower COUNTS on a public
-- profile come from a definer RPC (GLO-121), never from selecting this table —
-- otherwise the follow graph is scrapable one profile at a time.
create policy follows_read_own on follows for select
    to authenticated
    using (follower_id = (select auth.uid()) or followed_id = (select auth.uid()));

-- Minors cannot be followed: the edge grants nothing (their scopes are locked)
-- but it would let an adult assemble a list of minors.
create policy follows_insert_own on follows for insert
    to authenticated
    with check (follower_id = (select auth.uid()) and can_follow(followed_id));

-- Either party may remove the edge: unfollowing, or removing a follower
-- without escalating to a block.
create policy follows_delete_own on follows for delete
    to authenticated
    using (follower_id = (select auth.uid()) or followed_id = (select auth.uid()));

-- Read is deliberately blocker-only. `blocked_id = auth.uid()` is NOT here:
-- the blocked party must not be able to detect the block from data.
create policy blocks_own on blocks for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

create policy mutes_own on mutes for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Grants. Only the 2-arg wrapper reaches clients: the 3-arg core takes an
-- arbitrary viewer, and a client that could call it could probe any pair in the
-- graph. service_role keeps it for the link-card renderer (GLO-30 §6.2).
-- ---------------------------------------------------------------------------

-- REVOKE FROM anon AND authenticated EXPLICITLY, not just from public.
-- Supabase runs `alter default privileges in schema public grant execute on
-- functions to anon, authenticated, service_role`, so a new function arrives
-- with DIRECT grants to those roles — `revoke ... from public` does not touch
-- them and is a silent no-op. Verified on this migration: before the fix the
-- 3-arg can_view's ACL read
--   {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
-- with a from-public revoke already in the file.
revoke execute on function can_view(uuid, uuid, visibility_surface) from public, anon, authenticated;
revoke execute on function is_blocked(uuid, uuid)                   from public, anon, authenticated;
revoke execute on function is_mutual_follow(uuid, uuid)             from public, anon, authenticated;
revoke execute on function is_minor_user(uuid)                      from public, anon, authenticated;
revoke execute on function lock_minor_scopes()                      from public, anon, authenticated;
revoke execute on function sever_follows_on_block()                 from public, anon, authenticated;

-- is_minor(char(7), date) is deliberately NOT revoked. It is pure date
-- arithmetic over an input the caller already supplies — it maps no identity to
-- anything and reveals nothing you did not already know. is_minor_user(uuid) is
-- the one that turns a user id into minor status, and that one stays locked.
grant execute on function can_view(uuid, visibility_surface) to anon, authenticated;
grant execute on function can_follow(uuid) to authenticated;

comment on function can_view(uuid, visibility_surface) is
    'The single visibility predicate for Phase 1.5. Every public read policy calls this; none may hand-roll its own. GLO-115, docs/tech/02 §1.3.';
