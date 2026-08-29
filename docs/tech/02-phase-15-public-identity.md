# Phase 1.5 — Public Identity (text only)

The line crossed here: some user content becomes visible to other users — **text only**. Moderation surface = bios and usernames, a one-person-sized problem. Photos (looks) stay in Phase 2; **swatches ship here** (PRD §09) as the one photo exception, gated by the same pre-public moderation pipeline as Phase 2 in miniature (single content type, single reviewer).

Scope: privacy scope matrix · public profiles (rankings, shelf, collections as text) · following · routines (browse) · off-app link cards · trending · swatches · linked socials · report/block on profiles.

Tickets: [GLO-25](https://linear.app/glossed/issue/GLO-25) (the gate) · [GLO-27](https://linear.app/glossed/issue/GLO-27) · [GLO-28](https://linear.app/glossed/issue/GLO-28) · [GLO-29](https://linear.app/glossed/issue/GLO-29) · [GLO-30](https://linear.app/glossed/issue/GLO-30) · [GLO-31](https://linear.app/glossed/issue/GLO-31). This document is the build plan behind all six ([GLO-114](https://linear.app/glossed/issue/GLO-114)).

**Status of the SQL in this document: designed, not applied.** No migration file exists for any of it. The migration slot is a global lock across every session and Sean declined to open it the night this spec was written — deliberately. §11 lists what he has to rule on before the first `supabase/migrations/` file appears.

---

## 0. The gate, and why it is structural

[GLO-25](https://linear.app/glossed/issue/GLO-25) is not "first in the list." It is load-bearing in three ways that a later epic physically cannot route around:

1. **Every public read policy in 1.5 is written as `owner = auth.uid() OR can_view(owner, <surface>)`.** A migration that creates such a policy before `can_view()` exists fails at apply time — Postgres resolves the function at `CREATE POLICY`. The ordering is enforced by the database, not by a note in a ticket.
2. **`can_view()` is default-deny.** A user with no `privacy_scopes` row is `only_you` on all four surfaces. Shipping GLO-27's public profile before anyone has opted in exposes nothing, because the absence of a row is a *no*, not a missing answer.
3. **A meta-test asserts the shape** (§9, grid H): every SELECT policy on the 1.5 public set either restricts to the owner or calls `can_view`. A future epic that hand-rolls its own visibility predicate turns the suite red. That is what "the logic cannot fork" means operationally.

Nothing else in 1.5 may merge until 25.1 and 25.2 (§10) are on `main` and applied.

**Two axes stay separate** (PRD): **contribution** (feeds anonymous aggregates — always on, not a setting) vs **visibility** (attributed — always the user's choice). Nothing in this phase touches contribution.

---

## 1. Privacy: the scope matrix

### 1.1 Four surfaces, three scopes, and what rides which

The kit's `G.Privacy` frame draws exactly four rows. This spec adds no fifth.

| Surface | Covers | Notes |
|---|---|---|
| `shelf` | `user_items` (the products you own) | `want_to_try` rows are **never** published — see §2.1 |
| `rankings` | `rank_positions` (your face-off order) | `face_offs` themselves are never published, in any scope |
| `routines` | `routines` + `routine_steps` | |
| `looks` | nothing in 1.5 | Column ships here, default `only_you`; read by nothing until Phase 2. The frame already tags this row `v2`. |

**Collections do not get a profile-level scope.** `tech/02`'s earlier draft listed collections among the profile surfaces, but §6's whole growth argument is that "the collection link is the unit that spreads" — and a user whose shelf is `only_you` must still be able to share one collection. So collections publish **per collection**, like swatches: a `visibility` column on `collections`, defaulting to `only_you`. See §2.1.

**Publishing acts are per-act, not profile state**: posting a swatch, publishing a collection, and (Phase 2) commenting are each a decision at the moment of the act. They are not governed by `privacy_scopes`.

Enum vocabulary: **`only_you` / `friends` / `public`**, and the visible label is **"only you"**.

**This is a rename Sean made on Aug 29**, and it diverges from both the kit and the earlier drafts, so it is worth stating loudly: `G.Privacy` renders "just you" and uses `private` as its internal React key. Neither is the value. The schema is `only_you`, the label is "only you", and a screen built by copying the frame's string will be wrong. `domain.md` §1 is updated to match — it is the vocabulary source of truth, and this document follows it rather than the mock.

### 1.2 DDL — the privacy core

Ships in one migration (25.1). Nothing else in 1.5 may reference these objects before it applies.

```sql
-- 00XX · Privacy core: scopes, the graph, and the one visibility function.
-- GLO-25. docs/tech/02 §1. THE PHASE GATE — every 1.5 read policy calls
-- can_view(), and no policy may hand-roll its own predicate (§9 grid H).

create type scope_enum as enum ('only_you', 'friends', 'public');
create type visibility_surface as enum ('shelf', 'rankings', 'routines', 'looks');

create table privacy_scopes (
    user_id      uuid primary key references auth.users (id) on delete cascade,
    shelf        scope_enum not null default 'only_you',
    rankings     scope_enum not null default 'only_you',
    routines     scope_enum not null default 'only_you',
    looks        scope_enum not null default 'only_you',  -- inert until Phase 2
    discoverable boolean    not null default false,        -- surfaced in suggestions at all
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

-- Follow is not mutual. `friends` IS (§1.3) — these are different graphs.
create table follows (
    follower_id uuid not null references auth.users (id) on delete cascade,
    followed_id uuid not null references auth.users (id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (follower_id, followed_id),
    constraint follows_not_self check (follower_id <> followed_id)
);
create index follows_followed on follows (followed_id);

-- The blocked party must never be able to read this table. That is why
-- is_blocked() is security definer: can_view has to see rows the viewer cannot.
create table blocks (
    user_id    uuid not null references auth.users (id) on delete cascade,  -- the blocker
    blocked_id uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, blocked_id),
    constraint blocks_not_self check (user_id <> blocked_id)
);
create index blocks_blocked on blocks (blocked_id);

-- Mute suppresses someone from YOUR suggestions and trending rows. It changes
-- no visibility in either direction — that is the whole difference from block.
create table mutes (
    user_id   uuid not null references auth.users (id) on delete cascade,
    muted_id  uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, muted_id),
    constraint mutes_not_self check (user_id <> muted_id)
);
```

### 1.3 `can_view()` — the single function every policy calls

```sql
-- Order of evaluation is load-bearing and is asserted test-by-test in §9:
--   owner short-circuit → block → minor lock → scope → relationship.
-- Blocks beat `public`. The minor lock beats everything except the owner.
create or replace function can_view(p_viewer uuid, p_owner uuid, p_surface visibility_surface)
returns boolean
language plpgsql stable security definer set search_path = public as $$
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
    return is_mutual_follow(p_viewer, p_owner);   -- v_scope = 'friends'
end $$;

-- The RLS-facing wrapper. Literally delegates, so the logic cannot fork.
create or replace function can_view(p_owner uuid, p_surface visibility_surface)
returns boolean
language sql stable security definer set search_path = public as $$
    select can_view((select auth.uid()), p_owner, p_surface);
$$;

create or replace function is_blocked(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select p_a is not null and p_b is not null and exists (
        select 1 from blocks
         where (user_id = p_a and blocked_id = p_b)
            or (user_id = p_b and blocked_id = p_a));
$$;

create or replace function is_mutual_follow(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select p_a is not null and p_b is not null
       and exists (select 1 from follows where follower_id = p_a and followed_id = p_b)
       and exists (select 1 from follows where follower_id = p_b and followed_id = p_a);
$$;

-- Creation order for this migration, and the reason:
--   is_minor -> is_minor_user -> is_blocked -> is_mutual_follow
--   -> can_view(3-arg) -> can_view(2-arg) -> triggers -> RLS -> this revoke block.
-- can_view's 3-arg body is plpgsql, which is NOT resolved at CREATE FUNCTION
-- time, so it *could* forward-reference the helpers. The 2-arg wrapper is
-- `language sql` and IS resolved, so it must come after the 3-arg. Writing the
-- whole file dependency-first costs nothing and removes the question. (The same
-- trap bites §2.1 harder — see the ORDER MATTERS comment there.)
-- REVOKE FROM anon AND authenticated EXPLICITLY. `from public` alone is a
-- SILENT NO-OP on Supabase (see the two rules below).
revoke execute on function can_view(uuid, uuid, visibility_surface) from public, anon, authenticated;
revoke execute on function is_blocked(uuid, uuid)                   from public, anon, authenticated;
revoke execute on function is_mutual_follow(uuid, uuid)             from public, anon, authenticated;
revoke execute on function is_minor_user(uuid)                      from public, anon, authenticated;
grant  execute on function can_view(uuid, visibility_surface) to anon, authenticated;

-- A client-reachable wrapper for anything an RLS POLICY needs (see rule 2).
create or replace function can_follow(p_target uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select p_target is not null
       and p_target <> (select auth.uid())
       and not is_blocked((select auth.uid()), p_target)
       and not is_minor_user(p_target);
$$;
grant execute on function can_follow(uuid) to authenticated;
```

**Two rules that this spec got wrong until migration 0020 was actually run against Postgres.** Both were invisible to three adversarial reads of the SQL, and both are the kind that ship looking correct:

1. **`revoke ... from public` does nothing on Supabase.** Supabase runs `alter default privileges in schema public grant execute on functions to anon, authenticated, service_role`, so a new function arrives with **direct** grants to those roles. A from-public revoke does not touch a direct grant. Measured on 0020: the 3-arg `can_view`'s ACL still read `{postgres=X,anon=X,authenticated=X,service_role=X}` *with the revoke already in the file*. **Name `anon` and `authenticated` explicitly, and assert the ACL in a test** — this one fails silently and leaves a function you believe is private wide open.

2. **An RLS policy expression executes as the invoking user**, so a policy cannot call a function that user lacks `EXECUTE` on. 0020's `follows_insert_own` called `is_blocked` and `is_minor_user` — both correctly revoked — which made following **impossible for every user**. The fix is not to grant the helpers back: `is_blocked` would expose arbitrary block relationships and `is_minor_user` anyone's minor status. It is a **definer wrapper that answers only about `auth.uid()`** — `can_follow(target)` above, the same shape as `can_view`'s 2-arg wrapper. Any future 1.5 policy needing a privileged helper gets the same treatment.

A corollary worth stating because it is easy to over-apply: **`is_minor(char(7), date)` is deliberately NOT revoked.** It is pure date arithmetic over an input the caller already supplies — it maps no identity to anything. `is_minor_user(uuid)` is the one that turns a user id into minor status. Revoke the mapping, not the maths.

**Only the two-argument wrapper is granted to clients.** The three-argument core takes an arbitrary viewer; a client that could call it could probe any pair in the graph. It is granted to `service_role` only, because the link-card renderer (§6) needs to answer "can *this* viewer see this?" without a session.

**`friends` means mutual follow.** `tech/02`'s earlier draft said "`scope='friends'` AND follower relationship," which is ambiguous against a non-mutual follow model, and the permissive reading is a leak: if `friends` meant "anyone who follows me," any stranger self-serves into a friends-scoped shelf by tapping follow, and `friends` becomes a slower spelling of `public`. The word promises reciprocity, so the code requires it. **This is a spec ruling, not a restatement — §11 carries it for Sean's veto.**

**`discoverable` is deliberately absent from `can_view`.** It governs whether you are *surfaced to others* in suggestions, not whether anything of yours is readable. Folding it in would make a private-but-discoverable user unreachable, and a public-but-undiscoverable user impossible — both are valid states. The one asymmetry, stated at the toggle: to be surfaced you must be `discoverable`; private users still *receive* everything. (No "shade twin" naming — copy says "people in your shade can find you.")

**Performance rule.** `can_view` is called per row when it sits in an RLS `using` clause. Point reads are fine. **List endpoints go through security-definer RPCs that call `can_view` once per owner** — the `search_catalog` precedent (0005/0017/0019). A browse screen that filters a thousand rows through a per-row definer call is the wrong shape and will be caught in review.

### 1.4 The minors lock — twice, on purpose

`domain.md` §3.4: 13–17 is a restricted `user`. "Locked private by construction" means the read path does not trust the row.

```sql
-- Conservative by up to one month, deliberately (domain.md §6): certainly-18
-- starts on the 1st of the month after the 18th birthday could have occurred.
create or replace function is_minor(p_birth char(7), p_on date default current_date)
returns boolean language sql immutable parallel safe set search_path = public as $$
    select p_on < (to_date(p_birth || '-01', 'YYYY-MM-DD') + interval '18 years 1 month')::date;
$$;

-- No profile row is treated as a minor. Default-deny on the age gate too.
create or replace function is_minor_user(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select coalesce((select is_minor(p.birth_year_month) from profiles p where p.user_id = p_user), true);
$$;

-- Write side: a minor's row cannot hold a non-private value at all.
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
```

The write-side trigger is the polite half — it makes the UI's locked rows honest. **The load-bearing half is the read side**: `can_view` returns false for a minor owner before it ever looks at the scope row. A bad write, a service-role write, a future migration, or a bug in the app cannot leak a minor's shelf, because nothing on the read path consults the value the bug would have corrupted.

Minor status is computed live from `profiles.birth_year_month`. **`user_facts.minor` (0011) is an analytics snapshot and must never be the authority** — it is refreshed on a schedule, and a stale `false` there is a disclosure.

The rest of the minor surface, enforced where the write happens, not in the UI:

- Cannot post a swatch (§5, in the RLS `with check`).
- Cannot claim a handle (§3) — a handle *is* the public identity; there is nothing for a locked-private account to claim.
- **Cannot be followed.** Locking a minor private extends to the graph: a follow edge to a minor grants no visibility, but it does let an adult assemble a list of minors. `follows`' insert policy rejects it.
- Can follow, report, block, and mute (`domain.md` §4).
- Every blocked attempt emits `restricted_action_blocked{surface, action}` — already in the Phase-1 event vocabulary, already measured (tech/06 §3).

### 1.5 Blocks

A block is symmetric in effect and asymmetric in knowledge.

- `is_blocked` checks **both directions** and is consulted before scope, so a block beats `public`.
- Blocking severs the graph: an `after insert on blocks` trigger deletes `follows` rows in both directions. A block that leaves a follow edge standing is a bug that reads as a working feature.
- The blocked party cannot detect the block from data: `blocks` has no read policy for `blocked_id`, and every surface a blocked viewer requests answers "not found," never "blocked."
- Blocks suppress suggestions in both directions (§3).

### 1.6 RLS on the new tables

```sql
alter table privacy_scopes enable row level security;
alter table follows        enable row level security;
alter table blocks         enable row level security;
alter table mutes          enable row level security;

create policy privacy_scopes_own on privacy_scopes for all to authenticated
    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- You see your own edges, and only your own. Follower COUNTS on a public
-- profile come from a definer RPC (§3), never from selecting this table —
-- otherwise the follow graph is scrapable one profile at a time.
create policy follows_read_own on follows for select to authenticated
    using (follower_id = (select auth.uid()) or followed_id = (select auth.uid()));
create policy follows_insert_own on follows for insert to authenticated
    with check (follower_id = (select auth.uid())
                and not is_blocked((select auth.uid()), followed_id)
                and not is_minor_user(followed_id));
create policy follows_delete_own on follows for delete to authenticated
    using (follower_id = (select auth.uid()) or followed_id = (select auth.uid()));

create policy blocks_own on blocks for all to authenticated
    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy mutes_own on mutes for all to authenticated
    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
```

Note `follows_delete_own` allows the followed party to delete the edge — removing a follower without escalating to a block.

---

## 2. Public reads: the policy set, and the tables that never get one

### 2.1 The additive policy layer

Ships in 25.2. **No Phase-1 policy is modified.** Postgres ORs permissive policies together, so each table gains a second, SELECT-only policy alongside its existing owner-only one. The Phase-1 isolation suite (125 assertions) must stay green unchanged — if it moves, the change was not additive and the PR is wrong.

```sql
-- A user_item is published when the SHELF scope allows it, or when the item is
-- a step in a published routine / a row in a published list / a member of a
-- published collection. The second half is the bounded disclosure: publishing a
-- routine discloses the products IN that routine, not the whole shelf.
--
-- Definer, and not by accident: this reads routine_steps / rank_positions /
-- collection_items, which carry their own RLS. Calling them from inside a policy
-- on user_items without bypassing RLS is a mutual-recursion trap that resolves
-- to "invisible" and reads exactly like a working privacy feature.
-- ORDER MATTERS, and not for style. A `language sql` body is parsed and
-- resolved at CREATE FUNCTION time (check_function_bodies defaults to on), so
-- item_is_published cannot be created before collection_is_visible exists. A
-- `language plpgsql` body is NOT resolved then — which is why can_view (0001,
-- plpgsql) can forward-reference its helpers and this one cannot. Create in
-- this order: column, then plpgsql helper, then sql helper, then policies.
alter table collections add column visibility scope_enum not null default 'only_you';

create or replace function collection_is_visible(p_collection uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare v_owner uuid; v_vis scope_enum;
begin
    select user_id, visibility into v_owner, v_vis
      from collections where id = p_collection and deleted_at is null;
    if v_owner is null then return false; end if;
    if v_owner = (select auth.uid()) then return true; end if;
    if is_blocked((select auth.uid()), v_owner) then return false; end if;
    if is_minor_user(v_owner) then return false; end if;
    if v_vis = 'public' then return true; end if;
    if v_vis = 'friends' then return is_mutual_follow((select auth.uid()), v_owner); end if;
    return false;
end $$;

create or replace function item_is_published(p_item uuid, p_owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
    select (can_view(p_owner, 'routines') and exists (
                select 1 from routine_steps rs join routines r on r.id = rs.routine_id
                 where rs.user_item_id = p_item and r.user_id = p_owner and r.deleted_at is null))
        or (can_view(p_owner, 'rankings') and exists (
                select 1 from rank_positions rp
                 where rp.user_item_id = p_item and rp.user_id = p_owner))
        or exists (
                select 1 from collection_items ci join collections c on c.id = ci.collection_id
                 where ci.user_item_id = p_item and c.user_id = p_owner and c.deleted_at is null
                   and collection_is_visible(c.id));
$$;

create policy user_items_public on user_items for select to anon, authenticated
    using (deleted_at is null
           and ((status <> 'want_to_try' and can_view(user_id, 'shelf'))
                or item_is_published(id, user_id)));

create policy rank_positions_public on rank_positions for select to anon, authenticated
    using (can_view(user_id, 'rankings'));

create policy routines_public on routines for select to anon, authenticated
    using (deleted_at is null and can_view(user_id, 'routines'));

create policy routine_steps_public on routine_steps for select to anon, authenticated
    using (exists (select 1 from routines r
                    where r.id = routine_id and r.deleted_at is null
                      and can_view(r.user_id, 'routines')));

create policy collections_public on collections for select to anon, authenticated
    using (collection_is_visible(id));
create policy collection_items_public on collection_items for select to anon, authenticated
    using (collection_is_visible(collection_id));
```

`collection_is_visible` duplicates the *order* of `can_view`'s checks because a collection's scope lives on its own row rather than in `privacy_scopes`. That is the one permitted near-fork, and it earns its keep only if the block/minor/owner rules are the same three helper calls in the same order — grid H asserts exactly that.

**`want_to_try` is never published.** A wishlist is a wanting, not an owning, and nobody asked for theirs to be readable. GLO-100 already made want-to-try opt-in on the user's *own* shelf; publishing it to strangers by default would be the same mistake with a bigger blast radius. A user who wants to share a wishlist publishes a collection.

### 2.2 The tables that get no public policy, in any scope, ever

| Table | Why it stays owner-only |
|---|---|
| `profiles` | Holds Regulated fields (`birth_year_month`, `tone_band`, `skin_type`, `hair_pattern`). A public profile is served by an RPC that returns a projection (§3.3), never by relaxing RLS here. |
| `item_fits` | Fit is Regulated (`domain.md` §5, "anchors + fit"). A public shelf shows products, not how they fit you. The anchor *badge* is a separate, opt-in publication (§3.4). |
| `item_chips` | Experience chips are conditioned on body facts and week-stamped — Confidential, and the aggregate surfaces already carry the useful signal with no identifier attached. |
| `face_offs` | The pairwise history reveals more than the order does (what you compared, what you skipped, when). Rankings publish `rank_positions`. |
| `events`, `event_rollups_daily`, `user_facts` | No user grants at all (0011), and 1.5 adds none. |
| `blocks` | Read by the blocker only, forever (§1.5). |
| `reports` | Reporter reads own; reviewers use `service_role` (§7). |

### 2.3 The Regulated boundary, stated in the DDL

`domain.md` §5 says Regulated data is "never in logs." Phase 1 held that by convention plus a compiler-checked event enum. A phase whose point is publishing needs it as a constraint.

```sql
-- Events carry identifiers, not body facts. The client's Swift enum is the
-- first wall (core/Tracking); this is the second, and unlike the first it
-- also binds service-role writers and anything added later by hand.
alter table events add constraint events_no_regulated_props check (
    not (props ?| array[
        'tone_band', 'tone_band_at_capture', 'skin_type', 'hair_pattern', 'concerns',
        'birth_year_month', 'birthday', 'age', 'phone', 'email',
        'bio', 'handle', 'display_name', 'anchor_shade'
    ]));
```

Add it `not valid` and `validate constraint` in a second statement when this reaches hosted: the local `events` table already carries rows from Phase 1's tracking work, and a validating `ALTER` takes an `ACCESS EXCLUSIVE` lock while it scans every partition. The constraint binds new writes either way.

**The boundary this encodes is egress, not storage** — and getting that backwards is why an earlier draft of this list was wrong. `domain.md` §5's rule is that Regulated data never reaches *a log, an analytics prop sent outward, a breadcrumb, or a vendor*. It is not a rule against our own Postgres: `user_facts` (0011) deliberately stores `tone_band`, `skin_type` and `hair_pattern` precisely so the `events ⋈ user_facts` join stays in-house (`tech/06` §1).

So the list bans two things and not a third:

- **Free text and direct identity** — `bio`, `handle`, `display_name`, `phone`, `email`, `birthday`, `age`. These have no analytical use and every one of them is a disclosure if a prop ever reaches a log line.
- **Body facts that `user_facts` already holds** — `tone_band`, `skin_type`, `hair_pattern`, `concerns`, `anchor_shade`, `tone_band_at_capture`. Duplicating them into `props` buys nothing the join does not already give, and doubles the surface that has to stay in-house.
- **Not `fit` / `fits`.** An earlier draft banned these, which would have been a latent break: `Event.swift` already declares `onbAnchorCaptured(…, fit:)` → `"fit"` and `fitCaptured(fits:)` → `"fits"`. Neither has a call site *yet*, so the constraint would have passed CI, passed review, and then failed the day someone wired the fit events under a Phase-1 ticket — with an error pointing at a 1.5 migration. Fit is Regulated and stays in-house like the rest; it is not banned from `props`.

Note what the list also does not contain: `variant_id`, `category_id`, `user_id`, `followed_id`, `surface`, `scope`. Identifiers are the allowed currency.

One consequence to carry forward rather than resolve here: because `props` legitimately holds Regulated values, **`events` inherits Regulated classification for retention and deletion**, and `domain.md` §6's deletion list does not name `events` explicitly. That is a Phase-1 gap this spec surfaces but does not fix — it belongs on `BACKLOG.md`, not in a 1.5 migration.

Three consequences for 1.5 code, all of them reviewable:

- **`swatch_posted` carries `variant_id` and `state`, never `tone_band_at_capture`.** The snapshot lives on the row; the event does not.
- **The moderation Edge Functions (§7) must not log their payloads.** A bio going to a moderation model is Confidential text in transit; a `console.log(payload)` in a Deno function puts it in the Supabase log, which is the same disclosure as a Sentry breadcrumb wearing a different hat. Log the decision and the content hash, never the content.
- **Sentry breadcrumbs**: no screen that renders a profile, a badge, or a swatch may attach its model to a breadcrumb. Identifiers only, as everywhere else.

**Before relying on any of these, know that an event firing is currently unfalsifiable while driving.** [GLO-147](https://linear.app/glossed/issue/GLO-147): `track_ingest` returns 503 when nothing is serving functions locally, the `Tracker` then drops the batch **by design** (analytics must never cost UX — `tech/06` §2), and the drop is silent everywhere. A drive looks identical whether instrumentation works or is entirely dead.

Several 1.5 tickets carry acceptance criteria of the form *"`scope_changed` fires with `via_master`"*. **Those cannot be checked by driving alone.** Verifying an event in 1.5 means: a session-scoped `supabase functions serve` running (announced like a simulator borrow, output never `/dev/null`'d — `HANDOFF.md` §0), then a psql check that the row landed in `events`. Ticking the box off a drive alone proves nothing in either direction.

New 1.5 events, extending `tech/06` §3's "Phase 1.5+ additions" with their exact props:

| Event | Props | Reads |
|---|---|---|
| `scope_changed` | surface, from, to, via_master | how people actually use the matrix; whether the master is the real control |
| `discoverable_toggled` | to | the asymmetry's uptake |
| `handle_claimed` | — (no handle text) | publish funnel step 1 |
| `profile_published` | surfaces_public (count) | the actual conversion into public identity |
| `follow_added` / `follow_removed` | followed_id | graph growth, churn |
| `suggestion_shown` / `suggestion_tapped` | reason_kind (anchor/fit/domain) | whether named reasons beat unnamed ones |
| `swatch_posted` | variant_id, state | post rate; pending→public latency |
| `swatch_reported` / `report_filed` | subject_kind, reason | moderation load |
| `routine_browsed` | slot, filter_kind | whether browse filters get used at all — `filter_kind`, never the filter's value |
| `link_card_opened` | target_kind, resolved bool | server-side; CTR |
| `restricted_action_blocked` | surface, action | already exists — minors hitting 1.5 gates |

---

## 3. Handles, public profiles, following, suggested people (GLO-27)

### 3.1 Handles

Chosen at **first publish**, not at signup — V1 never needed one. There is **no handle-change flow in 1.5**, which is why there is no release/cooldown table: you cannot free a handle, so nobody can snipe one.

```sql
create table handles (
    user_id    uuid primary key references auth.users (id) on delete cascade,
    handle     text not null unique,       -- stored lowercase; the app never uppercases it
    claimed_at timestamptz not null default now(),
    constraint handle_shape check (handle ~ '^[a-z0-9][a-z0-9_.]{1,29}$' and handle !~ '\.\.')
);

create table reserved_handles (
    handle text primary key,
    reason text not null                    -- 'route' | 'brand' | 'impersonation' | 'safety'
);
```

`reserved_handles` seeds with **every top-level path segment the share domain will ever mint** (§6) — `c`, `p`, `u`, `v`, `api`, `app`, `www`, `admin`, `support`, `help`, `about`, `login`, `settings`, `terms`, `privacy`, `legal`, `glossed` — plus the safety set. Reserving the routes *before* the URL scheme ships is cheaper than discovering that `@c` collides with `/c/<slug>` after the first card is in the wild.

Impersonation is checked against data we already have: a handle equal to a `brands.normalized_name` is refused. 497 brands and growing means this gets stronger for free.

```sql
create or replace function claim_handle(p_handle text) returns text
language plpgsql security definer set search_path = public as $$
declare v_h text := lower(trim(p_handle));
begin
    if is_minor_user((select auth.uid())) then
        raise exception 'handles are a public identity' using errcode = 'check_violation';
    end if;
    if exists (select 1 from reserved_handles where handle = v_h)
       or exists (select 1 from brands where normalized_name = v_h) then
        raise exception 'handle reserved' using errcode = 'check_violation';
    end if;
    insert into handles (user_id, handle) values ((select auth.uid()), v_h);
    perform queue_text_moderation((select auth.uid()), 'handle', null, v_h);
    return v_h;
end $$;
grant execute on function claim_handle(text) to authenticated;
```

The unique index does the race; the client renders `23505` as "taken," which is why the *availability* check is advisory UI and the insert is the truth.

### 3.2 Moderated public text — one table, not four

Every user-authored string another user can see goes through one place. Sprinkling a `moderation_state` column across `profiles`, `handles`, `collections`, and `routines` guarantees the fifth one gets forgotten.

```sql
create type moderation_state as enum ('pending', 'approved', 'rejected');
create type public_text_kind as enum ('bio', 'handle', 'collection_title', 'routine_title', 'linked_social');

create table public_texts (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references auth.users (id) on delete cascade,
    kind       public_text_kind not null,
    subject_id uuid,                        -- collection/routine id; null for bio/handle
    body       text not null,
    state      moderation_state not null default 'pending',
    model      text, verdict jsonb, decided_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique nulls not distinct (user_id, kind, subject_id)   -- PG15+; config.toml pins 17
);
```

**The render rule, which is the whole point: a public surface reads only `state = 'approved'`.** A `pending` edit renders the previously approved body, or nothing — never the pending text. So the invariant "no unmoderated text is ever visible to another user" holds during the window between the write and the model's answer, which is where the naive design leaks.

### 3.3 The public profile RPC

`profiles` RLS never relaxes (§2.2). The public profile is a projection:

```sql
create or replace function public_profile(p_handle text)
returns table (handle text, display_name text, avatar_seed text, bio text,
               badge_skin_type text, badge_anchor text, badge_hair_pattern text,
               followers int, following int, shelf_n int, ranked_lists_n int,
               shelf_visible bool, rankings_visible bool, routines_visible bool)
language plpgsql stable security definer set search_path = public as $$ ... $$;
grant execute on function public_profile(text) to anon, authenticated;
```

What it must do, and what the tests in grid F assert:

- Returns **zero rows** — not an error, not a stub — when the handle is unclaimed, the owner is a minor, or a block exists in either direction. "Not found" and "blocked" are the same response, deliberately (§1.5).
- Emits a badge only when its opt-in flag is true **and** the owner is not a minor. Values are display strings ("combo", "fenty 240", "3b"), never the raw `profiles` row.
- `followers` / `following` are counts from this definer function. The client never selects `follows` for anyone but itself (§1.6) — that is what keeps the graph unscrapable.
- `shelf_n` and `ranked_lists_n` are **the n behind every claim the profile makes**. No count renders without one; no surface renders a claim it cannot count.
- `bio` comes from `public_texts` where `state = 'approved'`.

### 3.4 Badges are an opt-in publication of Regulated data

```sql
create table profile_badges (
    user_id           uuid primary key references auth.users (id) on delete cascade,
    show_skin_type    boolean not null default false,
    show_anchor       boolean not null default false,
    show_hair_pattern boolean not null default false
);
```

Regulated-class data may be *published by the user's own explicit act* — that is what "hideable badges" in the original §2 meant. (`show_anchor` additionally waits on [GLO-145](https://linear.app/glossed/issue/GLO-145): it publishes anchor evidence, and the view feeding it currently admits never-worn products — see §3.5.) The rule Regulated data never escapes is about logs, analytics props, and vendors, not about the user's own choice to wear their shade on their profile. All three flags default false; the badges are the only path by which `skin_type`, the anchor variant, and `hair_pattern` reach another human, and they still never reach an event prop (§2.3).

### 3.5 Following and suggested people

Follow is one-directional and needs no approval (`tech/02` original §2). `friends` scope needs both edges (§1.3). Contact import stays **out** until Phase 2 (post-activation only, PRD).

Suggested people, as an RPC, with every exclusion structural:

```sql
create or replace function suggested_people(p_limit int default 10)
returns table (user_id uuid, handle text, display_name text, reason text, reason_kind text, n int)
language sql stable security definer set search_path = public as $$ ... $$;
```

- Candidate set: users sharing your **anchor variant with an agreeing fit**, from the `user_shade_anchor` view, then same-domain/same-skin-type as the weaker fallback.
- ⚠️ **That view is not trustworthy yet, and 1.5 is where it stops being a private problem.** [GLO-145](https://linear.app/glossed/issue/GLO-145) found `user_shade_anchor` filters `c.is_anchor` and `deleted_at` but **not status**, so a fit captured on a `want_to_try` item becomes anchor evidence for a product the person has never worn — verified in psql on `9688e0a`, not inferred. In Phase 1 that corrupts a match. Here it corrupts **a sentence said to a stranger about someone**: this card's contract is a named reason, and the anchor badge (§3.4) publishes the same evidence on a profile. Both surfaces inherit the defect and neither may ship before GLO-145's view fix lands. If a 1.5 RPC has to run before that, it filters status itself and says so in a comment — silent inheritance is how a false claim gets shipped with a straight face.
- Excluded, by the query and asserted in tests: not `discoverable` · minors · blocked in either direction · muted · already followed · yourself.
- **The reason is named and carries its n**: "wears fenty 240 · ranks 14 things." A suggestion with no reason does not render. That is the design rule (one person with a reason, never a three-avatar grid) and the evidence rule (`EvidenceLine`) meeting on the same card.
- The Phase-2 `G.Feed` frame contains a follow button and "shade-twin cards." **It is not the reference for this card**: shade twins were removed in design review (`domain.md` §1, "Shade claim"), and the frame predates that. Build the suggestion card from the design system per the no-frames route (§8).

---

## 4. Routines browse + trending (GLO-28)

The routine object is unchanged from V1 (`slot am/pm/weekly/wash_day`, ordered steps, `started_on` — wash day is already first-class). 1.5 adds scope and two browse surfaces.

**Browse** — "AM routines from people with your skin," filtered by skin type / concerns, and by curl pattern for wash-day. Scope-respecting, n shown on every row.

```sql
create or replace function browse_routines(
    p_slot routine_slot, p_skin_type text default null, p_hair_pattern text default null,
    p_limit int default 20, p_cursor timestamptz default null)
returns table (routine_id uuid, title text, slot routine_slot, owner_handle text,
               step_n int, owner_shelf_n int, started_on date)
language sql stable security definer set search_path = public as $$ ... $$;
```

- One `can_view(owner, 'routines')` per candidate owner, not per row (§1.3's performance rule).
- `title` from `public_texts` where `state='approved'`; a routine whose title is pending does not appear in browse.
- Filters read the *viewer's own* profile for defaults; the filter values themselves are Regulated and must not ride in the `routine_browsed` event beyond `filter_kind`.
- Owner must be `discoverable` — browse is a surfacing surface, and §1.3's asymmetry applies to it exactly as it does to suggestions.

**Trending** — ownership/log velocity over a trailing window, overall and per skin type, rendered as cutout stickers. Aggregate, so it reads the identifier-free `agg_*` tables (0004), never `user_items` directly.

- **Min-n applies and is rendered, not hidden**: a row below the threshold says "not enough yet · k of N" the way the leaderboard does (`tech/01` §3), rather than vanishing.
- The window and the per-skin-type threshold are **numbers to tune with real data** — they join `docs/BACKLOG.md`'s "Aggregate min-n per surface" row rather than being invented here.
- Trending is *products*, not people. Nothing in it is scope-gated, because nothing in it is attributed.

---

## 5. Swatches (GLO-29)

The one photo surface of 1.5, behind a miniature of the Phase-2 pipeline.

```sql
create type swatch_state as enum ('pending_review', 'public', 'removed');

create table swatches (
    id                   uuid primary key default gen_random_uuid(),
    user_id              uuid not null references auth.users (id) on delete cascade,
    variant_id           uuid not null references variants (id),
    r2_key               text not null,
    tone_band_at_capture int check (tone_band_at_capture between 1 and 10),  -- SNAPSHOT
    state                swatch_state not null default 'pending_review',
    moderation           jsonb,
    posted_at            timestamptz,
    removed_at           timestamptz,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now()
);
create index swatches_variant_public on swatches (variant_id, tone_band_at_capture)
    where state = 'public';

alter table swatches enable row level security;

create policy swatches_own on swatches for all to authenticated
    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Tagged to the Variant, and only for variants on YOUR shelf. Minors cannot post.
create policy swatches_insert_own on swatches for insert to authenticated
    with check (user_id = (select auth.uid())
                and not is_minor_user((select auth.uid()))
                and exists (select 1 from user_items ui
                             where ui.user_id = (select auth.uid())
                               and ui.variant_id = swatches.variant_id
                               and ui.deleted_at is null));

-- A posted swatch is public because posting it was the act. Blocks still apply.
create policy swatches_public_read on swatches for select to anon, authenticated
    using (state = 'public' and not is_blocked((select auth.uid()), user_id));
```

- **`tone_band_at_capture` is snapshotted, never live-linked.** July tan stays filed correctly. A later profile edit does not move an old swatch between bands — asserted in grid G.
- The variant page groups swatches by tone band with the **viewer's own band expanded first**. The viewer's band comes from their anchors (or the fallback band); it is a render-order input and never leaves the device as an event prop.
- **Posting is a per-act publish**, and the confirm copy must say what the act does: posting shows your handle on that product page whatever your profile scope says. Attribution is inherent to posting; a user who does not want it should not post, and the button has to say so before the tap, not after.
- Pipeline: **EXIF strip on device** (already the standard, `domain.md` §5) → presigned upload (extends `storage_presign`) → cloud image moderation → `state='public'`. `pending_review` is never readable by anyone but the owner — the read policy tests `state = 'public'`, not `state <> 'removed'`, so a new state added later fails closed.
- Authenticity is **policy, not lock**: no AI-generated swatches, enforced by report + review; check C2PA metadata where present; claim no detection we cannot deliver. White balance is a volume problem, not fraud.
- Minors cannot post (in the `with check`, not in the UI). The blocked attempt emits `restricted_action_blocked{surface:'swatch', action:'photo_post'}`.
- Rate limiting per (user, variant) is **not** in the schema. It belongs in the posting RPC where it can return a real message; a unique constraint would render as an unexplained failure.

---

## 6. Off-app sharing + link cards (GLO-30)

Shareable URLs for collection / profile / product, with OG-image link cards rendered by an Edge Function (server-rendered PNG: cutout stickers + title + n). Universal links + Apple App Site Association + deep-link routing into the app (which also serves the existing share-in flows). One Edge-rendered public page per share target — no web app; the page says "open in the app."

### 6.1 The domain is an open decision and it blocks this epic

**`glossed.app` is taken** — verified during [GLO-89](https://linear.app/glossed/issue/GLO-89). Every `glossed.app/c/<slug>` in this document's earlier drafts referred to a domain we do not own and cannot get. Available at the time of that check: `glossed.beauty` ($1.99/yr) and `getglossed.app` ($9.99/yr). **This spec does not pick one** — see §11.

It has to be decided before GLO-30's first PR, not during it, because three things bind to it and one of them is irreversible:

| Binding | Reversible? |
|---|---|
| `apple-app-site-association`, served from the apex over HTTPS with no redirect | yes — redeploy |
| The `applinks:` associated-domains entitlement in `project.yml` | yes — rebuild |
| **Every share URL ever minted** | **no.** A card in someone's group chat points at the old host forever. |

Design so the code needs re-pointing rather than rewriting — one `ShareLinks.host` constant plus one function secret — but understand that this only limits the cost of a *late* change, it does not remove it. The minted URLs are the part that cannot be recalled.

### 6.2 Rendering respects scope at render time

The renderer has no session, so it uses the three-argument `can_view(viewer, owner, surface)` with `viewer = null` under `service_role`:

- Public target → the real card (stickers, title, n).
- Private target, blocked viewer, minor owner, unclaimed handle → **the same generic card**, with the same status code and the same latency. A card that 404s for private targets and 200s for public ones is a private-account oracle.
- `link_card_opened{target_kind, resolved}` is emitted server-side. `target_kind` only — no slug, no handle.
- The page renders the same n as the app. A claim on a link card is still a claim.
- **A profile card renders only what `public_profile()` returns — nothing else, ever.** The renderer holds `service_role` and no session, so it *could* read `profiles` straight through and assemble a nicer card. It must not. Every gate that matters lives in that RPC: the three badge opt-in flags, the minor lock, the block check, and (per §3.5) the anchor badge's dependency on GLO-145's view fix. Reading around the RPC re-implements all four by omission, on **the most public surface in the phase** — a card that unfurls in group chats, to people who have not opened the app and cannot be checked against anything.

  This is §6.2's existing rule extended one step: the renderer already never re-implements the *visibility* predicate. It must not re-implement the *content* projection either. Same reason both times — a second implementation is a second thing to keep correct, and this one is the copy that strangers see.
---

## 7. Moderation, report/block/mute, linked socials (GLO-31)

Report and block on profiles ship **day one of this phase** — the `blocks` table is in the gate migration (25.1) precisely because `can_view` cannot be written without it, so blocking is available the moment anything is visible.

```sql
create type report_state   as enum ('open', 'reviewing', 'actioned', 'dismissed');
create type report_subject as enum ('profile', 'handle', 'bio', 'collection', 'routine', 'swatch', 'linked_social');

-- Reports outlive the content they describe (T&S, 2 years — domain.md §6), and
-- survive account deletion with the personal fields gone. Hence `on delete set
-- null` on both user references rather than cascade.
create table reports (
    id              uuid primary key default gen_random_uuid(),
    reporter_id     uuid references auth.users (id) on delete set null,
    subject_kind    report_subject not null,
    subject_id      uuid,
    subject_user_id uuid references auth.users (id) on delete set null,
    reason          text not null check (reason in
                        ('impersonation', 'harassment', 'spam', 'nudity',
                         'ai_generated', 'underage', 'self_harm', 'other')),
    detail          text,
    state           report_state not null default 'open',
    decided_by      uuid, decided_at timestamptz, decision_note text,
    created_at      timestamptz not null default now()
);

alter table reports enable row level security;
create policy reports_insert_own on reports for insert to authenticated
    with check (reporter_id = (select auth.uid()));
create policy reports_read_own on reports for select to authenticated
    using (reporter_id = (select auth.uid()));
```

There is **no `reviewer` role in the database today**, and 1.5 does not add one. Adding an `authenticated` reviewer policy means adding a role, and that is a Phase-2-sized change. The `reviewer` row in `domain.md` §4's matrix is satisfied by `service_role` access until then, and this document says so rather than leaving the gap for someone to fill with a policy.

**Moderation v0 is Supabase Studio, and nothing else.** An earlier draft of this section said "Studio plus a small internal table UI" — that second half was an unowned deliverable: it appears in no PR plan in §10, and tracing §8's rows to their tickets is how it surfaced. Deciding rather than leaving it dangling:

- The queue is **one reviewer, two content types** (swatch images, and five kinds of `public_texts`). Studio's table editor handles that volume without ceremony.
- A bespoke internal UI is a new surface with its own auth, its own deploy target, and its own maintenance — none of which 1.5 otherwise needs, and all of which would be built for a queue that may never get deep.
- **The runbook is the interface** (GLO-31 5/5). A documented Studio procedure someone can follow beats an undocumented custom screen, and it is the artifact Phase 2 inherits either way.

The trigger for revisiting is volume, not taste: when working the queue in Studio costs more than about an hour a week, or when more than one person reviews, a purpose-built surface starts paying for itself. That is a Phase-2 signal and sits on `BACKLOG.md` accordingly.

**Text moderation at write time** covers bio, handle, collection titles, routine titles, and linked socials — all five kinds of `public_texts` (§3.2), through one Edge Function calling the Claude moderation prompt. It writes `state`, `model`, `verdict`, `decided_at` and **never logs `body`** (§2.3).

**Linked socials** (instagram/tiktok handles, plain links) are `public_text_kind = 'linked_social'` — the creator hook, and zero extra moderation weight because they ride the pipeline that already exists. They render as text, never as fetched previews: fetching a link on render is an SSRF surface and a tracking beacon in one.

**Runbooks written in this epic**, both in `docs/runbook.md` (which `BACKLOG.md` already has an open row for):

- The moderation runbook: queue triage, decision codes, the appeal path, and the notification rule (reporter + poster both told, `domain.md` §3.5).
- The **NCMEC runbook, drafted here ahead of Phase 2** — the first phase with user photos is the wrong place to start writing it.

---

## 8. Screen inventory — frame status

Verified against the kit on Aug 29 2026 by pulling `screens.jsx` and `screen-map.html` through the GetFile route (`docs/DESIGN.md` — `WebFetch` 403s). The kit holds **36 frames**. Exactly **two** are tagged `v15`, and both are the same screen in two states: `privacy · all four` and `privacy · mixed`. One frame is `v2` (`feed · looks · comments`). The other 33 are V1.

So: **one 1.5 screen has a frame, one has a stale frame, and 32 have none.**

| # | Screen | Ticket | Frame |
|---|---|---|---|
| 1 | Privacy scope matrix (four rows + `everything` master reading *mixed*) | GLO-25 | **exists** — `G.Privacy`, 2 map frames |
| 2 | `discoverable` toggle + its asymmetry copy | GLO-25 | **no frame** — see the gap note below |
| 3 | Minor privacy state (rows locked, explained) | GLO-25 | no frame |
| 4 | Handle claim at first publish | GLO-27 | no frame |
| 5 | Handle taken / reserved / impersonation error states | GLO-27 | no frame |
| 6 | **Public profile as another person sees it** | GLO-27 | **no frame** |
| 7 | Own profile gaining handle + follower/following counts | GLO-27 | **stale frame** — `G.Profile` exists but is own-profile-only and says so on screen |
| 8 | Badge visibility controls (skin type / anchor / hair) | GLO-27 | no frame |
| 9 | Follow / following button states | GLO-27 | no frame (`G.Feed` has a pattern; it is Phase 2 and carries dead vocabulary — §3.5) |
| 10 | Followers / following lists | GLO-27 | no frame |
| 11 | Suggested-people card (one person, named reason, n) | GLO-27 | no frame |
| 12 | Profile empty / blocked / not-found states | GLO-27 | no frame |
| 13 | Routines browse | GLO-28 | no frame |
| 14 | Someone else's routine detail | GLO-28 | no frame |
| 15 | Browse filters (skin type / concerns / curl pattern) | GLO-28 | no frame |
| 16 | Trending | GLO-28 | no frame |
| 17 | Swatch capture / camera-roll pick | GLO-29 | no frame |
| 18 | Swatch post confirm (per-act publish + attribution copy) | GLO-29 | no frame |
| 19 | Swatch pending-review state | GLO-29 | no frame |
| 20 | Variant page swatch grid by tone band, viewer's band first | GLO-29 | no frame (`G.Product` is V1 and has no swatch section) |
| 21 | Swatch viewer + report entry | GLO-29 | no frame |
| 22 | Minor blocked-from-posting state | GLO-29 | no frame |
| 23 | Share sheet (collection / profile / product) | GLO-30 | no frame |
| 24 | Web share page — public target | GLO-30 | no frame |
| 25 | Web share page — private/generic target | GLO-30 | no frame |
| 26 | OG link card artwork | GLO-30 | no frame |
| 27 | Deep-link cold open / app-not-installed | GLO-30 | no frame |
| 28 | Report sheet (reason picker) | GLO-31 | no frame |
| 29 | Report filed / under-review confirmation | GLO-31 | no frame |
| 30 | Block confirm + blocked-list management | GLO-31 | no frame |
| 31 | Mute control | GLO-31 | no frame |
| 32 | Linked socials edit | GLO-31 | no frame |
| 33 | Moderation queue (internal) | GLO-31 | **not a screen** — Supabase Studio only in v0 (§7); the runbook is the interface. No frame needed and none wanted. |
| 34 | Content removed / under review | GLO-31 | no frame |

**The gap inside the frame that exists.** `G.Privacy` draws the four surface rows, the master, the per-row dots and the save button — and **no `discoverable` row**. The one asymmetry this phase has to state at the toggle has nowhere to live in the frame. Row 2 is therefore a real design question, not a formality, and it sits inside the one screen everybody would assume is covered.

**Three things the frame says that the schema does not**, and all three get built wrong by someone reading the frame as a spec:

1. Its demo state is `{looks: private, shelf: friends, rankings: friends, routines: private}`. That is a mock's illustrative state, **not the default** — the default is `only_you` on all four (§1.2).
2. Its internal key for the first scope is `private`. The schema value is `only_you`.
3. **It renders the label "just you." The label is now "only you"** (Sean, Aug 29 — §1.1). The frame predates the rename, so the one screen with a frame is also the one screen whose visible string must not be copied from it.

None of these is a bug in the kit. They are the cost of a frame drawn before the vocabulary settled, and they are why §1.1 says this document follows `domain.md` rather than the mock.

**This list is the ask.** Phase 1's no-frames ruling (GLO-16, Aug 28: *"I won't be adding frames for it, based off the current design system, make tickets for these and build them"*) covered specific V1 screens. It has not been extended to 1.5. Sean rules per §11: supply frames for some subset, or extend the ruling, screen by screen or wholesale. Until then, rows 2–34 are all in the position `docs/DESIGN.md` describes: *if you are about to build a screen and cannot open the frame for it, stop and say so.*

---

## 9. The viewer-pair RLS test grid

Phase 1's isolation suite is the model: 125 assertions, pgTAP, `begin … rollback`, `test_as(uid)` setting `request.jwt.claims`. 1.5's suite extends it to **pairs** — Phase 1 only ever had to prove that nobody sees anything.

**Target: ≥ 171 assertions across 7 files.** The count is a floor, not a budget.

**Fixtures live inside the test transaction, not in `seed.sql`.** The grid needs nine actors; the seed has two. Inserting the extra `auth.users` rows inside each test's transaction (rolled back at the end) keeps the seed unchanged — which matters, because a seed change means a `supabase db reset`, and the restore is six scripts and roughly fifty minutes on a database three sessions share.

### 9.1 The actors

| Actor | Relationship to the owner |
|---|---|
| `owner` | maya (`…0001`) — adult, the subject of every row |
| `minor_owner` | `birth_year_month` inside the 18-year window |
| `mutual` | juli (`…0002`) — follows owner **and** is followed by owner |
| `follower_only` | follows owner; owner does not follow back |
| `followed_only` | owner follows them; they do not follow owner |
| `stranger` | no edges |
| `blocked_by_owner` | `blocks(owner → them)` |
| `blocker_of_owner` | `blocks(them → owner)` |
| `anon` | no JWT at all (the link-card and web-page path) |

### 9.2 Grid A — `can_view(viewer, owner, 'shelf')` · 24 assertions

`✓` visible, `·` not.

| scope ↓ / viewer → | owner | mutual | follower_only | followed_only | stranger | anon |
|---|---|---|---|---|---|---|
| **no row** | ✓ | · | · | · | · | · |
| `only_you` | ✓ | · | · | · | · | · |
| `friends` | ✓ | **✓** | · | · | · | · |
| `public` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

The `friends` row is the whole reason this grid exists: `follower_only` is **not** a friend. One-way follow does not buy visibility (§1.3). If a future change makes that cell `✓`, `friends` has silently become `public`.

### 9.3 Grid B — the surface switch · 16 assertions

Each of `shelf` / `rankings` / `routines` / `looks`, at `friends` and at `public`, for `mutual` and `stranger`. Two properties: the surfaces are independent (setting one does not move another), and `looks` behaves identically to the rest even though nothing reads it in 1.5 — so Phase 2 inherits a tested column rather than a new one.

### 9.4 Grid C — blocks · 21 assertions

| block state ↓ / (scope, viewer) → | (`friends`, mutual) | (`friends`, stranger) | (`public`, mutual) | (`public`, stranger) |
|---|---|---|---|---|
| none | ✓ | · | ✓ | ✓ |
| owner → viewer | · | · | · | · |
| viewer → owner | · | · | · | · |
| both directions | · | · | · | · |

**Every cell below the first row is `·`.** A block beats `public`, and it beats it from either side — the blocked party loses visibility just as the blocker does. Plus five behavioural assertions: inserting a block deletes both follow edges; the blocked party cannot select `blocks`; a re-follow after a block is rejected by the insert policy; `blocked_by_owner` gets zero rows (never an error) from `public_profile`; and a block is invisible to the blocked party on every surface.

### 9.5 Grid D — the minors lock · 25 assertions

- `minor_owner` × 4 scopes × {mutual, stranger, anon} = **12 assertions, all `·`** — including the scopes a minor's row cannot legally hold, written directly through `service_role` to prove the *read* side does not trust the row (§1.4).
- `minor_owner` sees all four of their own surfaces (4).
- The write trigger rejects each of the four non-`only_you` surfaces and `discoverable = true` (5).
- A user with **no `profiles` row** is treated as a minor (1).
- Nobody can insert a `follows` row targeting a minor (1).
- `claim_handle` refuses a minor (1).
- A minor's swatch insert is refused by the `with check` (1).

### 9.6 Grid E — the real tables · 38 assertions

The six publishable tables (`user_items`, `rank_positions`, `routines`, `routine_steps`, `collections`, `collection_items`) × {stranger at `public`, stranger at `only_you`, mutual at `friends`, blocked at `public`} = 24. Then:

- `want_to_try` rows never appear to a stranger even at `shelf = public` (1).
- Soft-deleted rows never appear (1).
- An item **not** on a public shelf appears when it is a step in a published routine (1), a row in a published list (1), or a member of a published collection (1) — the bounded disclosure of §2.1.
- `face_offs` are invisible to every non-owner at every scope (3).
- `item_fits` (2), `item_chips` (2), and `profiles` (2) are invisible to every non-owner at every scope.

### 9.7 Grid F — `public_profile()` and badges · 15 assertions

All three badge flags default false (3); each badge appears only when its flag is true (3); badges are withheld from a blocked viewer (1); a minor's handle returns **zero rows** (1); an unclaimed handle returns zero rows (1); a `pending` bio does not render (1); an `approved` bio does (1); a pending *edit* still renders the previously approved body (1); and the return type carries no `birth_year_month`, no raw `tone_band`, and no phone (3).

### 9.8 Grid G — swatches · 11 assertions

Insert requires the variant on your own shelf (2); a minor cannot insert (1); `pending_review` is unreadable by a stranger and by a mutual (2); `public` is readable by a stranger (1); a blocked viewer cannot read a public swatch (1); `removed` is unreadable (1); the owner reads their own pending swatch (1); changing `profiles.tone_band` does not move an existing swatch's `tone_band_at_capture` (1); a report can be filed against a swatch (1).

### 9.9 Grid H — the shape of the thing · 21 assertions

This is the grid that keeps the logic from forking, and it tests the schema rather than the data:

- Every SELECT policy on the 1.5 public set either restricts to the owner or names `can_view` — a single assertion over `pg_policies.qual` that goes red the day someone hand-rolls a predicate (1).
- No public read policy exists on `profiles`, `item_fits`, `item_chips`, or `face_offs` (4).
- The three-argument `can_view` is not executable by `authenticated` (1); neither are `is_blocked`, `is_mutual_follow`, or `is_minor_user` (3).
- `events_no_regulated_props` rejects an insert carrying each of `tone_band`, `skin_type`, `hair_pattern`, `bio`, `display_name` (5) — **and accepts one carrying `fit` and `fits`**, which is the assertion that stops the ban list creeping back over Phase-1's own events (1).
- A fresh `privacy_scopes` row defaults to `only_you` on all four surfaces and `discoverable = false` (5).
- `collection_is_visible` refuses in the same three cases and the same order as `can_view` — owner, block, minor (1).

---

## 10. Ticket breakdown — the PR plan

Every PR is ≤5 files / ≤400 lines unless it says otherwise. **Two PRs need the migration slot, and the slot is a global lock across every session** — 25.1 and 25.2 are strictly sequential, and each is a separate acquisition. That is a scheduling cost, stated here rather than discovered later.

Swift PRs follow the pattern this codebase has proven twice (`ShelfFitStore`, `ShelfChipStore`): a **feature-side closure seam** first, so the model and the screen are fully testable and drivable in picker states with `core/DataKit` untouched, and live wiring becomes one `repository(_:)` factory once the core supplies the call. No 1.5 PR *builds* against a DataKit opening — but every one of them eventually *wires* against one, and that bill is itemised below rather than discovered per-ticket.

### 10.1 The Phase-1.5 DataKit opening bundle

`core/DataKit` opened once already (#192 — chips, notes, like state, and `invokeEdgeFunctionForData`). That does **not** cover 1.5, and the reason is structural: **every RPC in DataKit is a bespoke, typed repository method** — `search_catalog`, `near_matches`, `capture_fit` — and there is no generic `rpc(name:params:)` on the public surface. That is deliberate (`DataKit.swift`: "every query in the app goes through DataKit's repositories, so there is exactly one place session handling can be got wrong"), and it means a new RPC is a new method, every time.

1.5 introduces roughly **nineteen calls that do not exist**, across four new repository files:

| Repository | Calls | For |
|---|---|---|
| `PrivacyRepository` | `scopes()` · `setScope(surface:to:)` · `setAllScopes(to:)` · `setDiscoverable(_:)` | GLO-25 5/5 |
| `SocialRepository` | `claimHandle(_:)` · `myHandle()` · `publicProfile(handle:)` · `follow` / `unfollow` · `suggestedPeople(limit:)` · `badges()` / `setBadge(_:to:)` · `block` / `unblock` / `blockedUsers()` · `mute` / `unmute` · `report(...)` · `setPublicText(kind:subjectID:body:)` | GLO-27, GLO-31 |
| `BrowseRepository` | `browseRoutines(...)` · `trending(...)` | GLO-28 |
| `SwatchRepository` | `swatches(variantID:)` · `postSwatch(...)` · `mySwatches()` | GLO-29 |

Two things follow, and both are cheaper to know now than to hit later:

- **The upload half is already open.** `invokeEdgeFunctionForData` (#192) is exactly what GLO-29's presign call needs — swatch upload needs no new opening, only the swatch *rows* do.
- **This is a bigger ask than Phase 1's opening bundle**, which was four chip calls plus `like_state` plus one invoke. Openings are per-session authorizations, so nineteen methods across four files wants to be **one deliberate bundle**, sized and approved in advance — not nineteen separate asks discovered one screen at a time. `docs/HANDOFF.md` §8 already carries "planned against a core that couldn't supply" as a scar; this section exists so 1.5 does not re-earn it.

The seam-first pattern still holds and is still the right first move: it keeps each Swift PR small, testable, and mergeable while the bundle is being negotiated. It just is not a substitute for the bundle.

### GLO-25 — privacy scope matrix + `can_view` (the gate) · 5 PRs

| PR | Contents | Files | Notes |
|---|---|---|---|
| 25.1 | Migration `privacy_core`: enums, `privacy_scopes`, `follows`, `blocks`, `mutes`, `is_minor`, `is_minor_user`, `is_blocked`, `is_mutual_follow`, both `can_view` arities, the minor-lock trigger, the block→unfollow trigger, RLS on the four new tables | 2 | **migration slot** |
| 25.2 | Migration `privacy_public_reads`: `item_is_published`, `collection_is_visible`, `collections.visibility`, the six public SELECT policies, `events_no_regulated_props` | 2 | **migration slot**, strictly after 25.1 |
| 25.3 | pgTAP grids A+B (`privacy_can_view.test.sql`) and H (`privacy_policy_shape.test.sql`) — 60 assertions | 2 | no migration |
| 25.4 | pgTAP grids C (`privacy_blocks.test.sql`) and D (`privacy_minors.test.sql`) — 46 assertions | 2 | parallel-safe with 25.3 |
| 25.5 | `features/Profile`: the privacy matrix screen against a `PrivacyScopeStore` seam — four rows, the derived `mixed` master, the `discoverable` row, the minor locked state | 4–5 | **frame exists for the four rows only** (§8 rows 1–3) |

Acceptance: `can_view` is the only visibility predicate in the schema (grid H); every default is `only_you`; the master is derived and never stored; a minor's rows are locked in the UI *and* refused by the trigger *and* ignored by the read path; the Phase-1 125-assertion suite is untouched and green.

### GLO-27 — handles, public profiles, following, suggested people · 6 PRs

| PR | Contents | Files |
|---|---|---|
| 27.1 | Migration: `handles`, `reserved_handles` (+ route and safety seed), `public_texts`, `profile_badges`, `claim_handle()` | 2 |
| 27.2 | Migration: `public_profile()` RPC + follower/following count functions; pgTAP grid F | 2 |
| 27.3 | Migration: `suggested_people()` RPC with every exclusion in the query; pgTAP for the exclusion set | 2 |
| 27.4 | Swift: handle claim screen + taken/reserved/impersonation states | 3–4 |
| 27.5 | Swift: own profile gains handle + follower/following counts + badge visibility controls | 4 |
| 27.6 | Swift: viewed public profile, follow/unfollow button states, suggested-people card | 4–5 |

Acceptance: the follow graph is not scrapable (counts come from the RPC; `follows` selects only your own edges); a suggestion never renders without a named reason and its n; no badge renders unless its flag is on; unclaimed handle, minor, and blocked all return zero rows identically; handles are lowercase-unique and refuse routes and brand names.

### GLO-28 — routines browse + trending · 4 PRs

| PR | Contents | Files |
|---|---|---|
| 28.1 | Migration: `browse_routines()` — scope-respecting, `discoverable`-gated, approved-titles-only; pgTAP | 2 |
| 28.2 | Migration: trending RPC over `agg_*` with the min-n rule rendered, not hidden; pgTAP | 2 |
| 28.3 | Swift: routines browse + filters + someone else's routine detail | 4–5 |
| 28.4 | Swift: trending surface, cutout stickers, n on every row | 3–4 |

Acceptance: browse never returns a routine whose owner's scope forbids it or whose title is unmoderated; the window and thresholds are recorded as open numbers (`BACKLOG.md`), not invented; every row carries its n; a below-threshold row says so rather than vanishing.

### GLO-29 — swatches end to end · 5 PRs

| PR | Contents | Files |
|---|---|---|
| 29.1 | Migration: `swatches`, `swatch_state`, RLS (shelf-ownership + minor gate in the `with check`); pgTAP grid G | 2 |
| 29.2 | Edge Function: image moderation `pending_review → public/removed`, no payload logging; deno tests | 3 |
| 29.3 | `storage_presign` extended to swatch keys (non-guessable, per-user); deno tests | 2–3 |
| 29.4 | Swift: capture / camera-roll pick, EXIF strip, upload, post confirm with the attribution copy | 4–5 |
| 29.5 | Swift: variant-page swatch grid by tone band, viewer's band first, report entry | 3–4 |

Acceptance: `pending_review` is invisible to everyone but the owner; the band is snapshotted and provably immune to a later profile edit; minors are refused at the database, not the button; EXIF is stripped before upload; the post confirm states the attribution before the tap.

### GLO-30 — link cards, universal links, web share pages · 5 PRs

**Blocked at PR 1 on the domain decision (§6.1, §11).**

| PR | Contents | Files |
|---|---|---|
| 30.1 | The domain: AASA served from the apex, `applinks:` entitlement, `ShareLinks.host` as one constant | 3 |
| 30.2 | Edge Function: share page per target kind, scope-respecting via three-arg `can_view`; deno tests incl. the generic-card path | 3 |
| 30.3 | Edge Function: OG image render (stickers + title + n); deno tests | 2–3 |
| 30.4 | Swift: deep-link routing (cold open, app-not-installed), reusing the share-in resolver | 3–4 |
| 30.5 | Swift: share sheet for collection / profile / product | 3–4 |

Acceptance: a private target and a public one are indistinguishable from outside (same status, same shape, same latency); every card carries its n; no slug or handle in `link_card_opened`; the AASA is served from the apex with no redirect.

### GLO-31 — report/block/mute, moderation v0, linked socials · 5 PRs

`blocks` and `mutes` already exist from 25.1; this epic builds everything above them.

| PR | Contents | Files |
|---|---|---|
| 31.1 | Migration: `reports`, enums, RLS (insert own / read own; reviewers via `service_role`); pgTAP | 2 |
| 31.2 | Edge Function: text moderation over all five `public_texts` kinds, decision + hash logged, body never; deno tests | 3 |
| 31.3 | Swift: report sheet, block confirm, post-report state | 4 |
| 31.4 | Swift: blocked-list management, mute control, linked-socials edit | 4 |
| 31.5 | `docs/runbook.md`: moderation runbook + NCMEC runbook draft | 1 |

Acceptance: a report survives the deletion of its subject's account with personal fields nulled; no unmoderated text is ever visible to another user (the `approved`-only render rule); linked socials render as text and are never fetched; the two runbooks exist before Phase 2 starts.

---

## 11. Open decisions — Sean's, not this document's

| # | Decision | Why it cannot be defaulted |
|---|---|---|
| 1 | ~~The share domain~~ — **RESOLVED (Sean, Aug 29): a reach, deferred.** `glossed.app` is taken; no domain is being bought yet and GLO-30 is not being picked up until later. | Recorded on GLO-30 and its five sub-issues. The bindings in §6.1 stand for whenever it is revisited — the irreversibility of minted URLs does not expire. |
| 2 | **Frames for 1.5.** 32 of 34 screens have none (§8). Supply frames, or extend Phase 1's no-frames ruling to 1.5 — wholesale or row by row. | `docs/DESIGN.md`'s standing rule is *stop and say so*. GLO-27 through GLO-31 are UI-blocked until this is answered. |
| 3 | **The `discoverable` row has no frame** even though the privacy screen does. | It is the one screen everyone would assume is covered, and the asymmetry copy has nowhere to live (§8). |
| 4 | ~~`friends` = mutual follow~~ — **CONFIRMED (Sean, Aug 29).** | Stands as specified in §1.3. |
| 5 | ~~Collections publish per collection~~ — **CONFIRMED (Sean, Aug 29).** | Stands as specified in §1.1 and §2.1. |
| 6 | ~~`want_to_try` is never published~~ — **CONFIRMED (Sean, Aug 29), explicitly "for now — this may change later."** | Stands as specified in §2.1. Written as one predicate in one policy, so revisiting it is a one-line change rather than an archaeology exercise. |
| 7 | **The migration slot, twice.** 25.1 and 25.2 are sequential acquisitions of a global lock. | Sean declined the slot the night this was written. Nothing in 1.5 starts until it opens. |
| 8 | **Trending window + per-skin-type min-n.** Not invented here; they join `BACKLOG.md`'s open-numbers list. | Phase 1's data is what tunes them, and it now exists. |
| 9 | **The 1.5 DataKit opening bundle** — ~19 methods across four new repository files (§10.1). | Openings are per-session authorizations. Nineteen methods wants one sized, approved bundle, not nineteen asks found one screen at a time. |

---

## 12. Definition of done

- [ ] Scope matrix live, RLS enforced by `can_view()`, and grid H proving no policy forks the logic
- [ ] Viewer-pair suite at ≥171 assertions, green, with the Phase-1 125 untouched
- [ ] Minors locked private on the read path, the write path, and the graph
- [ ] Handles, public profiles, following, suggested people with named reasons and their n
- [ ] Routines browse; trending with min-n rendered rather than hidden
- [ ] Swatches end to end with pre-public moderation; band snapshotted; minors refused at the database
- [ ] Link cards + universal links, private and public targets indistinguishable from outside
- [ ] Report/block/mute live; moderation runbook written; NCMEC runbook drafted ahead of Phase 2
- [ ] No Regulated field in any event prop, log line, or breadcrumb — enforced by `events_no_regulated_props`, not by review
