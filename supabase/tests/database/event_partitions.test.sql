-- events partition grants (0033). GLO-150.
--
-- The bug was invisible because every check anyone would think to run was run
-- against the PARENT, and the parent was correct. Partitions inherit neither
-- RLS nor ACLs, so `events` being locked said nothing about events_2026_08.
--
-- The assertion that matters most is the last group: a NEWLY MINTED partition.
-- Locking today's partitions fixes today; ensure_events_partition() runs every
-- month, and an unfixed one regenerates the hole on a schedule with nobody
-- watching. Checking only existing partitions would pass forever while the
-- next one arrives wide open.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

-- ---------------------------------------------------------------------------
-- The parent, which was never the problem. Regression cover only.
-- ---------------------------------------------------------------------------

select ok(not has_table_privilege('anon', 'public.events', 'select'),
    'anon cannot read the events parent');
select ok((select relrowsecurity from pg_class where relname = 'events'),
    'RLS is enabled on the parent');

-- ---------------------------------------------------------------------------
-- Every existing partition, found by catalog rather than by name. Hard-coding
-- events_2026_08 would pass in September and prove nothing.
-- ---------------------------------------------------------------------------

select is(
    (select count(*)::int
       from pg_class c
       join pg_inherits i on i.inhrelid = c.oid
       join pg_class p on p.oid = i.inhparent
      where p.relname = 'events'
        and (has_table_privilege('anon', c.oid, 'select')
          or has_table_privilege('authenticated', c.oid, 'select'))), 0,
    'NO events partition is readable by anon or authenticated. This is the bug: the parent was locked and every partition was not, because a partition inherits neither RLS nor ACLs and Supabase default privileges hand every new table to anon');

select is(
    (select count(*)::int
       from pg_class c
       join pg_inherits i on i.inhrelid = c.oid
       join pg_class p on p.oid = i.inhparent
      where p.relname = 'events' and not c.relrowsecurity), 0,
    'every existing partition has RLS enabled');

select is(
    (select count(*)::int
       from pg_class c
       join pg_inherits i on i.inhrelid = c.oid
       join pg_class p on p.oid = i.inhparent
      where p.relname = 'events' and not c.relforcerowsecurity), 0,
    'and RLS FORCED, not merely enabled — events is written under service_role, and an owner bypasses its own RLS without force. Enable alone leaves a table that reads as protected in pg_class and is not for the role that touches it most');

select is(
    (select count(*)::int
       from pg_class c
       join pg_inherits i on i.inhrelid = c.oid
       join pg_class p on p.oid = i.inhparent
      where p.relname = 'events'
        and (has_table_privilege('anon', c.oid, 'insert')
          or has_table_privilege('anon', c.oid, 'update')
          or has_table_privilege('anon', c.oid, 'delete'))), 0,
    'and anon holds no write privilege on any partition either — the original sweep found SELECT, but default privileges grant all four');

-- ---------------------------------------------------------------------------
-- The two functions. drop_expired_event_partitions() destroys twelve months of
-- analytics; ensure_events_partition() creates tables.
-- ---------------------------------------------------------------------------

select ok(not has_function_privilege('anon', 'drop_expired_event_partitions()', 'execute'),
    'anon cannot drop twelve months of analytics');
select ok(not has_function_privilege('authenticated', 'drop_expired_event_partitions()', 'execute'),
    'and neither can a signed-in user — this is a maintenance job, not a feature');
select ok(not has_function_privilege('anon', 'ensure_events_partition(date)', 'execute'),
    'anon cannot mint partitions');
select ok(not has_function_privilege('authenticated', 'ensure_events_partition(date)', 'execute'),
    'and neither can a signed-in user');

-- ---------------------------------------------------------------------------
-- THE ONE THAT STOPS THIS COMING BACK.
--
-- Mint a partition for a month that does not exist yet and inspect what was
-- born. Every assertion above passes on a codebase where the lock is a one-off
-- sweep — this is the only group that fails on one.
--
-- The transaction rolls back, so the partition does not survive the test.
-- ---------------------------------------------------------------------------

select lives_ok($$ select ensure_events_partition('2027-03-01'::date) $$,
    'a future partition can be minted');

select ok(
    (select count(*) from pg_class where relname = 'events_2027_03') = 1,
    'and it exists');

select ok(not has_table_privilege('anon', 'public.events_2027_03', 'select'),
    'A NEWLY MINTED PARTITION IS NOT READABLE BY anon. Before 0033 this was born readable — verified by minting one. The lock has to live inside ensure_events_partition(), because that function runs monthly and anything that only fixes the partitions that exist today reopens the hole on the first of next month');

select ok(not has_table_privilege('authenticated', 'public.events_2027_03', 'select'),
    'nor by authenticated');

select ok((select relrowsecurity from pg_class where relname = 'events_2027_03'),
    'a newly minted partition has RLS enabled at birth, not at the next audit');

select ok((select relforcerowsecurity from pg_class where relname = 'events_2027_03'),
    'and forced');

-- Idempotence: ensure_events_partition runs for the current and next month on
-- every deploy, so it re-runs against tables that already exist. The lock
-- statements must survive that.
select lives_ok($$ select ensure_events_partition('2027-03-01'::date) $$,
    'minting the same partition twice is safe — revoke, enable and force are all idempotent, which they must be because this function re-runs against existing tables on every deploy');

select ok(not has_table_privilege('anon', 'public.events_2027_03', 'select'),
    'and the second run leaves it locked, not re-opened');

select finish();
rollback;
