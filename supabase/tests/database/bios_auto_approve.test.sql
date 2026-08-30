-- bios_auto_approve() and the writer it gates (0045). GLO-207.
--
-- The point of this file is the OFF position. Turning auto-approve on is the
-- easy half and the app proves it every time someone saves a bio; what nobody
-- would otherwise exercise is the switch that has to be flipped before public
-- launch. A reversal that has never been run is not a reversal, it is an
-- intention.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set ana '00000000-0000-0000-0000-0000000000a7'

select set_config('role', 'postgres', true);
delete from public_texts where user_id = :'ana';
delete from profiles     where user_id = :'ana';
delete from auth.users   where id = :'ana';
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values (:'ana', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'ana@local.test', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');

select test_as(:'ana');
insert into profiles (user_id, birth_year_month, domains) values (:'ana', '1994-02', '{makeup}');

-- ---------------------------------------------------------------------------
-- ON — the beta position, and the one shipping today.
-- ---------------------------------------------------------------------------
select ok(bios_auto_approve(), 'auto-approve ships ON: the beta cohort is closed and nothing reviews text');

select test_as(:'ana');
select set_public_text('bio', null, 'first bio');
select is((select state::text from public_texts where user_id = :'ana' and kind = 'bio'), 'approved',
    'a bio lands approved rather than pending — otherwise it would never render, with no error shown');

-- The marking is what makes the eventual backfill a query rather than a guess.
select ok((select verdict -> 'auto_approved' = 'true'::jsonb from public_texts
            where user_id = :'ana' and kind = 'bio'),
    'and is MARKED auto-approved, so "every bio nobody has read" stays answerable');
select is((select model from public_texts where user_id = :'ana' and kind = 'bio'), null,
    'model stays null — no model ran, and naming one would claim a review that did not happen');

select test_as(:'ana');
select set_public_text('bio', null, 'edited bio');
select is((select state::text from public_texts where user_id = :'ana' and kind = 'bio'), 'approved',
    'an edit lands approved too — there is no review to re-enter');

-- ---------------------------------------------------------------------------
-- Scope: the ruling was about bios. Nothing else moved.
-- ---------------------------------------------------------------------------
select test_as(:'ana');
select set_public_text('handle', null, 'ana_h');
select is((select state::text from public_texts where user_id = :'ana' and kind = 'handle'), 'pending',
    'a handle still lands pending — it is a review record, not a gate, and the ruling did not mention it');

-- ---------------------------------------------------------------------------
-- OFF — what must happen before public launch. This is the half worth having.
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
create or replace function bios_auto_approve() returns boolean
language sql immutable as $$ select false $$;

select test_as(:'ana');
select set_public_text('bio', null, 'written after the beta ends');
select is((select state::text from public_texts where user_id = :'ana' and kind = 'bio'), 'pending',
    'with the switch OFF a bio lands pending again — one line, and the gate is back');
select is((select verdict from public_texts where user_id = :'ana' and kind = 'bio'), null,
    'and carries no verdict, because nothing decided anything');

select test_as(:'ana');
select is((select bio from public_profile('ana_h')), null,
    'so it does not render either — the reader never changed, only when a bio passes the gate');

select finish();
rollback;
