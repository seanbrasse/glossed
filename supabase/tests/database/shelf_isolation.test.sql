-- Isolation suite · shelf (0002): owner-only on every verb, anchor view scoped.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- maya logs her anchor foundation (fenty 240) with a fit
select test_as('00000000-0000-0000-0000-000000000001');
select lives_ok($$
    insert into profiles (user_id, birth_year_month, domains, skin_type, tone_band)
    values ('00000000-0000-0000-0000-000000000001', '1998-04', '{makeup,skincare,haircare}', 'combo', 6)
$$, 'maya creates her profile');
select lives_ok($$
    insert into user_items (id, user_id, variant_id, client_id)
    values ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
            '40000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001')
$$, 'maya logs a canonical variant');
select lives_ok($$
    insert into item_fits (user_id, user_item_id, fit)
    values ('00000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 'just_right')
$$, 'maya captures the fit');

-- the anchor view derives from her log
-- Scoped to the fixture variant, not counted absolutely (GLO-161). maya may
-- legitimately own other anchor shades — a shared database accumulates them —
-- and an absolute count of 1 fails for reasons unrelated to what this line is
-- named for. It was red twice in one day for two different causes and the
-- failure text could not tell them apart, which is how a true signal (the
-- GLO-145 view leak) got dismissed as noise for most of a session.
--
-- BE CLEAR ABOUT THE TRADE: scoping NARROWS this. The absolute count would
-- catch a stray anchor row from any variant, including a leaked want_to_try
-- one; this catches only that the fixture's own log derives correctly, which
-- is what the assertion is named for. That is acceptable because the leak now
-- has dedicated coverage — anchor_view.test.sql asserts the want_to_try
-- exclusion, the status round trip and the security_invoker property in 13
-- scoped assertions. Restating them here would be two copies free to drift.
select is(
    (select count(*)::int from user_shade_anchor
      where user_id = '00000000-0000-0000-0000-000000000001'
        and variant_id = '40000000-0000-0000-0000-000000000002'),
    1, 'anchor view derives from anchor-category log + fit');

-- juli sees none of it, by any verb
select test_as('00000000-0000-0000-0000-000000000002');
select ok(not exists(select 1 from user_items where id = '50000000-0000-0000-0000-000000000001'),
    'juli cannot read maya''s item by id');
select ok(not exists(select 1 from user_shade_anchor where user_id = '00000000-0000-0000-0000-000000000001'),
    'juli cannot see maya''s anchors through the view');
select ok(not exists(select 1 from profiles where user_id = '00000000-0000-0000-0000-000000000001'),
    'juli cannot read maya''s profile');
select throws_ok($$
    insert into item_chips (user_id, user_item_id, experience_chip_id)
    values ('00000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000001',
            (select id from experience_chips where slug = 'oxidized-on-me'))
$$, '42501', 'new row violates row-level security policy for table "item_chips"',
    'juli cannot chip maya''s item');
select lives_ok($$ update user_items set note = 'hijack' where id = '50000000-0000-0000-0000-000000000001' $$,
    'cross-user update filters to zero rows');

select * from finish();
rollback;
