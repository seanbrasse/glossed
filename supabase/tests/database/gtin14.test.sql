-- Suite · GTIN-14 (0010). GLO-58.
begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

-- The seed's fenty 240 row stores a 13-digit code; its generated form is 14.
select is((select gtin14 from variants where id = '40000000-0000-0000-0000-000000000002'),
    '00810086012350', 'a stored EAN-13 reads back left-padded to 14');

-- The lookup that was failing: a US UPC-A scan (12 digits), padded by the
-- client to 14, finds the European row.
select is((select id from variants where gtin14 = lpad('810086012350', 14, '0')),
    '40000000-0000-0000-0000-000000000002'::uuid,
    'a UPC-A scan finds the EAN-13 row through the padded form');

-- A variant with no code has no padded code, not a string of zeros.
select is((select gtin14 from variants where id = '40000000-0000-0000-0000-000000000004'),
    null, 'no gtin, no gtin14');

-- Two codes differing only by leading zeros are one product twice — a feed
-- bug the index refuses. (service role: canonical writes are not user-facing)
reset role;
select throws_like($$
    insert into variants (product_id, kind, gtin)
    values ('30000000-0000-0000-0000-000000000001', 'shade', '810086012350')
$$, '%variants_gtin14%',
    'a code that pads to an existing one is refused as a duplicate');

-- The original-length uniqueness still stands for exact feed duplicates.
select throws_like($$
    insert into variants (product_id, kind, gtin)
    values ('30000000-0000-0000-0000-000000000001', 'shade', '0810086012350')
$$, '%variants_gtin_key%',
    'the original unique on gtin still catches same-length duplicates');

select * from finish();
rollback;
