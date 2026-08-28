-- 0010 · GTINs compare at 14 digits. GLO-58.
--
-- The same physical product carries a 12-digit UPC-A in the US and a 13-digit
-- EAN-13 elsewhere — the same GTIN, differing by leading zeros. `variants.gtin`
-- stores whatever the feed supplied and the barcode rung matched it exactly,
-- so a US scan of a European row reported `unknownCode`: real demand for a
-- product already stocked, written into the failed-search queue as a gap that
-- is not one.
--
-- GS1's canonical form is GTIN-14, left-padded. The stored column keeps the
-- feed's original form (its uniqueness still catches feed duplicates at the
-- original length); the generated column is what lookups match.

alter table variants add column gtin14 text
    generated always as (lpad(gtin, 14, '0')) stored;

-- Unique where present: two variants whose codes differ only by leading zeros
-- are one product twice, and that is a feed bug this index now refuses.
create unique index variants_gtin14 on variants (gtin14) where gtin14 is not null;

-- `submitted_gtin` (0008) deliberately gets no generated column and no
-- uniqueness: it is an unverified user claim, and late-binding promotion reads
-- it with its own padding. Constraining it would give the second scanner of a
-- missing barcode a conflict — the exact failure submitted_gtin exists to avoid.
