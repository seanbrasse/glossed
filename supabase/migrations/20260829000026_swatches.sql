-- 0026 · Swatches — the one photo surface of Phase 1.5. GLO-130.
-- docs/tech/02 §5.
--
-- A miniature of the Phase-2 pipeline: EXIF strip on device -> presigned upload
-- -> cloud image moderation -> public. Single content type, single reviewer.
--
-- Every gate below lives in the POLICY, not the button. Hiding a control is
-- presentation (domain.md §4); this is where the rules actually hold.

create type swatch_state as enum ('pending_review', 'public', 'removed');

create table swatches (
    id                   uuid primary key default gen_random_uuid(),
    user_id              uuid not null references auth.users (id) on delete cascade,
    variant_id           uuid not null references variants (id),
    r2_key               text not null,
    -- SNAPSHOTTED at capture, never live-linked. July tan stays filed
    -- correctly: a later profiles.tone_band edit does not move an old swatch
    -- between bands. A foreign key or a view here would give exactly the
    -- opposite behaviour, which is why this is a plain column.
    tone_band_at_capture int check (tone_band_at_capture between 1 and 10),
    state                swatch_state not null default 'pending_review',
    moderation           jsonb,
    posted_at            timestamptz,
    removed_at           timestamptz,
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now()
);

-- The variant page groups by band with the viewer's own band expanded first,
-- so this index matches the read shape rather than the write shape.
create index swatches_variant_public on swatches (variant_id, tone_band_at_capture)
    where state = 'public';
create index swatches_user on swatches (user_id);

-- ---------------------------------------------------------------------------
-- Client-reachable gate wrappers.
--
-- RLS policy expressions execute as the INVOKING user, so a policy cannot name
-- is_minor_user or is_blocked — both are revoked from clients on purpose
-- (0020), and granting them back would expose anyone's minor status and
-- arbitrary block relationships. Each wrapper is definer and answers ONLY
-- about auth.uid(), the can_view/can_follow doctrine.
-- ---------------------------------------------------------------------------

-- May the CALLER post a swatch for this variant? Encodes both write gates:
-- minors cannot post at all, and you may only swatch a variant on your own
-- shelf. A caller learns this by trying, so the wrapper reveals nothing new.
create or replace function can_post_swatch(p_variant uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select (select auth.uid()) is not null
       and not is_minor_user((select auth.uid()))
       and exists (
            select 1 from user_items ui
             where ui.user_id = (select auth.uid())
               and ui.variant_id = p_variant
               and ui.deleted_at is null);
$$;

-- Is the CALLER blocked with respect to this owner, in either direction?
-- Posting is a per-act publish, so a public swatch is public regardless of
-- profile scope — but a block still severs it.
create or replace function viewer_blocked_by(p_owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select is_blocked((select auth.uid()), p_owner);
$$;

alter table swatches enable row level security;

-- The owner sees and manages their own, including pending ones.
--
-- DELIBERATELY NOT `for all`. A `for all` policy also covers INSERT, and its
-- with-check would be satisfied by `user_id = auth.uid()` alone — which ORs
-- with the gated insert policy below and lets a MINOR post a swatch. Permissive
-- policies combine with OR, so a broad policy does not merely duplicate a
-- narrow one, it DEFEATS it. Caught by the minor test; do not collapse these
-- three back into one.
create policy swatches_read_own on swatches for select
    to authenticated
    using (user_id = (select auth.uid()));

create policy swatches_update_own on swatches for update
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

create policy swatches_delete_own on swatches for delete
    to authenticated
    using (user_id = (select auth.uid()));

-- Both write gates, in the policy rather than the app.
create policy swatches_insert_own on swatches for insert
    to authenticated
    with check (user_id = (select auth.uid()) and can_post_swatch(variant_id));

-- THE READ POLICY TESTS state = 'public', NOT state <> 'removed'.
--
-- That is deliberate and is the line most likely to be "simplified" later: a
-- state added in future (say 'appealed') then fails CLOSED rather than
-- becoming publicly readable by default. Do not invert this.
create policy swatches_public_read on swatches for select
    to anon, authenticated
    using (state = 'public' and not viewer_blocked_by(user_id));

-- Full intended ACL per object. Both wrappers are policy-facing, so clients
-- must be able to execute them or the policies break outright.
revoke execute on function can_post_swatch(uuid)     from public, anon, authenticated;
revoke execute on function viewer_blocked_by(uuid)   from public, anon, authenticated;

grant execute on function can_post_swatch(uuid)   to authenticated;
grant execute on function viewer_blocked_by(uuid) to anon, authenticated;

comment on column swatches.tone_band_at_capture is
    'Snapshotted at capture, never live-linked — a later profile edit must not move an old swatch between bands. GLO-130, docs/tech/02 §5.';
comment on policy swatches_public_read on swatches is
    'Tests state = ''public'', NOT state <> ''removed'', so a state added later fails closed rather than becoming publicly readable.';
