-- Suite · merge queue holds feed rows (0012). GLO-14 PR 2.
begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

-- A product pair still works.
reset role;
select lives_ok($$
    insert into merge_candidates (product_a, product_b, similarity)
    values ('30000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000008', 0.9)
$$, 'a product pair queues');

-- A feed-row pair works.
select lives_ok($$
    insert into merge_candidates (product_a, feed_row, similarity)
    values ('30000000-0000-0000-0000-000000000001',
            '{"brand":"fenty beauty","name":"pro filtr soft matte foundation"}', 0.7)
$$, 'a feed row queues without manufacturing a product');

-- Exactly one counterpart, never both, never neither.
select throws_ok($$
    insert into merge_candidates (product_a, product_b, feed_row, similarity)
    values ('30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', '{}', 0.7)
$$, '23514', null, 'both counterparts is refused');
select throws_ok($$
    insert into merge_candidates (product_a, similarity)
    values ('30000000-0000-0000-0000-000000000001', 0.7)
$$, '23514', null, 'neither counterpart is refused');

select * from finish();
rollback;
