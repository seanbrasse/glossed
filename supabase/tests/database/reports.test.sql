-- Reports (0028). GLO-140.
--
-- The interesting property is not who can file — it is what SURVIVES. A report
-- is institutional memory about something having been said, so it has to
-- outlive both the content and the accounts involved.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya '00000000-0000-0000-0000-000000000001'
\set juli '00000000-0000-0000-0000-000000000002'
\set gone '00000000-0000-0000-0000-0000000000e9'

select set_config('role', 'postgres', true);
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values (:'gone', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'gone@local.test', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');

-- ---------------------------------------------------------------------------
-- Filing
-- ---------------------------------------------------------------------------
select test_as(:'maya');
select lives_ok($$
    insert into reports (id, reporter_id, subject_kind, subject_user_id, reason)
    values ('70000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001',
            'profile', '00000000-0000-0000-0000-000000000002', 'harassment')
$$, 'maya can file a report');

select throws_ok($$
    insert into reports (reporter_id, subject_kind, reason)
    values ('00000000-0000-0000-0000-000000000002', 'profile', 'spam')
$$, '42501', 'new row violates row-level security policy for table "reports"',
    'you cannot file a report in someone else''s name');

select throws_ok($$
    insert into reports (reporter_id, subject_kind, reason)
    values ('00000000-0000-0000-0000-000000000001', 'profile', 'because i said so')
$$, '23514', null, 'the reason must be one of the eight — free text goes in `detail`, not `reason`');

-- ---------------------------------------------------------------------------
-- A filed report is not editable or retractable by its reporter. It is a record
-- of something having been said.
-- ---------------------------------------------------------------------------
select is((select count(*)::int from pg_policies
            where tablename = 'reports' and cmd in ('UPDATE','DELETE','ALL')), 0,
    'there is NO update, delete, or `for all` policy on reports — a broad policy would OR with the narrow ones, which is how a minor got to post a swatch in 0026');

select lives_ok($$ update reports set state = 'dismissed'
                    where id = '70000000-0000-0000-0000-0000000000b1' $$,
    'a self-dismiss runs without error — RLS filters it to zero rows rather than raising');
select is((select state::text from reports where id = '70000000-0000-0000-0000-0000000000b1'), 'open',
    'and it changed NOTHING — a reporter cannot decide their own report');

select lives_ok($$ delete from reports where id = '70000000-0000-0000-0000-0000000000b1' $$,
    'a self-delete likewise runs');
select is((select count(*)::int from reports where id = '70000000-0000-0000-0000-0000000000b1'), 1,
    'and the report is still there — it cannot be retracted');

-- ---------------------------------------------------------------------------
-- Isolation
-- ---------------------------------------------------------------------------
select test_as(:'juli');
select is((select count(*)::int from reports where id = '70000000-0000-0000-0000-0000000000b1'), 0,
    'the SUBJECT of a report cannot read it — being reported is not a notification channel');

-- ---------------------------------------------------------------------------
-- THE PROPERTY THIS TABLE EXISTS FOR: the record outlives the people in it.
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
insert into reports (id, reporter_id, subject_kind, subject_user_id, reason, detail)
values ('70000000-0000-0000-0000-0000000000b2', :'gone', 'swatch', :'gone', 'ai_generated', 'kept');

delete from auth.users where id = :'gone';

select is((select count(*)::int from reports where id = '70000000-0000-0000-0000-0000000000b2'), 1,
    'deleting BOTH the reporter and the subject leaves the report standing — a cascade would delete the moderation record along with the account it exists to remember');
select is((select reporter_id from reports where id = '70000000-0000-0000-0000-0000000000b2'), null,
    'reporter_id is nulled, not cascaded — the identity is the perishable part');
select is((select subject_user_id from reports where id = '70000000-0000-0000-0000-0000000000b2'), null,
    'subject_user_id likewise');
select is((select detail from reports where id = '70000000-0000-0000-0000-0000000000b2'), 'kept',
    'and the substance survives — 2-year T&S retention needs the WHAT, not the WHO');

-- ---------------------------------------------------------------------------
-- No reviewer role was created, and privilege agrees with policy.
-- ---------------------------------------------------------------------------
select is((select count(*)::int from pg_roles where rolname = 'reviewer'), 0,
    'no `reviewer` role exists — moderation v0 is Studio as service_role, and adding a role is Phase-2-sized');
select ok(not has_table_privilege('anon','public.reports','select'),
    'anon has no privilege on reports — reporting requires an account, and privilege agrees with policy at creation this time');
select ok(not has_table_privilege('anon','public.reports','insert'),
    'nor insert');

select * from finish();
rollback;
