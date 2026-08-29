-- 0033 · Lock the events partitions, and lock the ones not born yet.
-- GLO-150. Authorized by Sean, Aug 29.
--
-- 0011 enabled RLS on `events` and revoked it from clients. Neither reaches a
-- partition: PARTITIONS INHERIT NEITHER RLS NOR ACLs. Each one is created by
-- ensure_events_partition() as an ordinary table, and Supabase's default
-- privileges hand every new table to anon and authenticated. The parent being
-- correctly locked is exactly what made this invisible — every check anyone
-- would think to run was run against `events` and passed.
--
-- Demonstrated on the local stack rather than inferred, `set role anon`:
--
--   AS ANON — rows readable from events_2026_08: 6
--   AS ANON — user_id=00000000… name=item_status_changed
--             props={"to": "finished", "from": "own", "variant_id": "4622e170-…"}
--
-- This is Regulated data by this repo's own reasoning. BACKLOG.md: props
-- legitimately carries fit/fits on Phase-1's own events, so `events` inherits
-- Regulated classification — and events_no_regulated_props bans fourteen keys
-- while deliberately NOT banning those. So the table is designed to hold
-- Regulated values, and anon could read it. domain.md §5 requires access
-- control on exactly that.
--
-- THE FIX IS IN THE MINTING FUNCTION, NOT A SWEEP. A sweep over today's two
-- partitions fixes today. Proven by minting one:
--     select ensure_events_partition('2026-10-01');
--     new partition anon-readable: true · new partition RLS: false
-- ensure_events_partition() runs monthly, so an unfixed one regenerates the
-- hole on a schedule with nobody watching. Same class as the security_invoker
-- trap in 0031: silence is a grant, and only an assertion makes it audible.
--
-- NOTE FOR REVIEW: this migration is NOT purely additive. It changes the body
-- of a function that runs monthly. Flagged to Sean before authorization.

-- ---------------------------------------------------------------------------
-- The minting function, which is the actual fix.
--
-- `if not exists` means the lock statements must be idempotent too — this is
-- called for the current and next month on every run, usually finding the
-- table already there. revoke, enable rls and force rls are all safe to repeat.
--
-- FORCE row level security, not merely enable: `events` is written by
-- track_ingest under service_role, and the partition owner would otherwise
-- bypass its own RLS. Enable alone would leave a table that looks protected in
-- pg_class and is not for the role that touches it most.
-- ---------------------------------------------------------------------------
create or replace function ensure_events_partition(p_month date)
returns void language plpgsql security definer set search_path = public as $$
declare
    v_start date := date_trunc('month', p_month)::date;
    v_end date := (v_start + interval '1 month')::date;
    v_name text := 'events_' || to_char(v_start, 'YYYY_MM');
begin
    execute format(
        'create table if not exists %I partition of events for values from (%L) to (%L)',
        v_name, v_start, v_end);

    -- A partition is born readable by anon. Close it in the same breath that
    -- creates it, so there is no window and no monthly regression.
    execute format('revoke all on table %I from anon, authenticated', v_name);
    execute format('alter table %I enable row level security', v_name);
    execute format('alter table %I force row level security', v_name);
end $$;

-- ---------------------------------------------------------------------------
-- The partitions that already exist. Found by catalog, not by name: hard-coding
-- events_2026_08 and _09 would miss anything minted between this file being
-- written and being applied, and would silently do nothing on an environment
-- whose months differ.
-- ---------------------------------------------------------------------------
do $$
declare
    v_partition record;
begin
    for v_partition in
        select c.relname
          from pg_class c
          join pg_inherits i on i.inhrelid = c.oid
          join pg_class p on p.oid = i.inhparent
         where p.relname = 'events'
    loop
        execute format('revoke all on table %I from anon, authenticated', v_partition.relname);
        execute format('alter table %I enable row level security', v_partition.relname);
        execute format('alter table %I force row level security', v_partition.relname);
    end loop;
end $$;

-- ---------------------------------------------------------------------------
-- The destructive RPC. Dropping twelve months of analytics is not a thing an
-- unauthenticated caller should be able to ask for. Named explicitly rather
-- than revoked `from public`, which is a silent no-op against Supabase's
-- default privileges (the lesson of 0022 and 0024).
-- ---------------------------------------------------------------------------
revoke execute on function drop_expired_event_partitions() from public, anon, authenticated;
revoke execute on function ensure_events_partition(date)    from public, anon, authenticated;

comment on function ensure_events_partition(date) is
    'Creates the month partition AND locks it — revoke from clients, enable and force RLS. The lock lives here because a partition inherits neither RLS nor ACLs, so anything that only fixes existing partitions regenerates the hole next month (GLO-150).';
