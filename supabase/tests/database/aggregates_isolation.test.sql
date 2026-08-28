-- Isolation suite · aggregates/ops (0004): users touch nothing directly;
-- the payoff RPC is the only door and it enforces min-n.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- service seeds aggregate rows (as postgres/service role, before impersonation)
insert into agg_variant_stats (variant_id, owners, fit_counts) values
    ('40000000-0000-0000-0000-000000000002', 12, '{"just_right": 9, "too_light": 3}'), -- fenty 240: above min-n
    ('40000000-0000-0000-0000-000000000004', 3, '{"just_right": 1}');                  -- soft pinch joy: below

-- authenticated users cannot read or write aggregate/ops tables directly
select test_as('00000000-0000-0000-0000-000000000001');
select is((select count(*)::int from agg_variant_stats), 0, 'aggregates unreadable directly (no policy)');
select is((select count(*)::int from ingest_jobs), 0, 'ops tables unreadable directly');
select throws_ok($$ insert into agg_variant_stats (variant_id, owners) values ('40000000-0000-0000-0000-000000000001', 999) $$,
    '42501', 'new row violates row-level security policy for table "agg_variant_stats"',
    'users cannot write aggregates');

-- the payoff RPC is the door, and it carries the evidence gate
select is((select n_exact_shade from payoff_for_variant('40000000-0000-0000-0000-000000000002')), 12,
    'payoff returns the n through the definer RPC');
select is((select evidence_backed from payoff_for_variant('40000000-0000-0000-0000-000000000002')), true,
    'n=12 clears the min_n_payoff() gate');
select is((select evidence_backed from payoff_for_variant('40000000-0000-0000-0000-000000000004')), false,
    'n=3 does not clear the gate — client must render the neutral fallback');
select is((select n_with_fit from payoff_for_variant('40000000-0000-0000-0000-000000000002')), 12,
    'fit counts sum through the RPC');

select * from finish();
rollback;
