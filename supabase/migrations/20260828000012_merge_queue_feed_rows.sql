-- 0012 · The merge queue learns to hold a feed row. GLO-14 PR 2.
--
-- Dedupe's middle band (tech/01 §4) is a *pair*: an existing product and a
-- thing that might be the same product. When the thing is another product row,
-- product_b carries it. When it is a feed row — the common case for ingest —
-- there is deliberately no product yet: writing one just to queue it would
-- manufacture the duplicate the queue exists to prevent, and `products.scope
-- = 'submitted'` requires a human creator the feed does not have.
--
-- So product_b becomes nullable and the feed row rides in its own column.
-- Exactly one of the two is present.

alter table merge_candidates alter column product_b drop not null;
alter table merge_candidates add column feed_row jsonb;
alter table merge_candidates add constraint merge_candidates_one_counterpart
    check ((product_b is null) <> (feed_row is null));

-- The adjudicator's outcome for a feed row, by verb (tech/01 §4, PRD §16):
--   merge          → the row's price/availability apply to product_a's variant
--   attach_variant → a new variant under product_a
--   fork           → a new canonical product, forked_from product_a
-- Verdicts and application are the Edge Function's job; the queue just holds
-- the pair, the band, and the decision trail.
comment on column merge_candidates.feed_row is
    'The unmatched feed row, when the counterpart is not a product yet. GLO-14.';

-- Ingest needs to find pending work cheaply.
create index merge_candidates_pending on merge_candidates (created_at)
    where state = 'pending';
