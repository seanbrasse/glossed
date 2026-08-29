-- 0031 · The anchor view stops carrying never-worn evidence.
-- GLO-145, half 2 (the data half; the UI half shipped in #200).
--
-- user_shade_anchor filtered `c.is_anchor AND ui.deleted_at IS NULL` and NOT
-- status, so a fit captured on a want_to_try item became anchor evidence. The
-- shade-matching spine reads this view (tech/01 §1.2, domain.md §3.1), and
-- tech/01 §2 puts it plainly: one weak early claim poisons every good one after
-- it. "We only match shades people have actually worn" was a claim the data
-- did not support.
--
-- THE OPEN QUESTION ON GLO-145, answered as the ticket recommended.
-- When a tried item moves back to want_to_try, its fit row SURVIVES and simply
-- stops counting as evidence. The table is the log; the view is the evidence
-- surface. Deleting the fit would destroy true history to fix a display
-- problem, and status is exactly the field a user flips by accident. The app
-- already behaves this way — a want_to_try → own → want_to_try round trip
-- through the sheet preserves item_fits (verified on the drive, session 8) —
-- so this migration makes the view agree with behaviour that already exists
-- rather than introducing a new rule.
--
-- Only want_to_try is excluded. `finished` and `repurchased` are worn: the
-- shade was on the person's face, and that is what makes it evidence.

-- `with (security_invoker = true)` IS LOAD-BEARING AND IS NOT DECORATION.
-- CREATE OR REPLACE VIEW does not inherit the original's options: 0002 declared
-- this view security_invoker, and replacing it without restating that silently
-- reverts it to running as its OWNER, which bypasses RLS on user_items and lets
-- any authenticated user read every other user's anchors. Writing this file
-- without the clause did exactly that, and shelf_isolation's "juli cannot see
-- maya's anchors through the view" caught it — the assertion earns its place.
create or replace view user_shade_anchor with (security_invoker = true) as
    select ui.user_id, ui.variant_id, f.fit, f.season, f.captured_at
      from user_items ui
      join item_fits f  on f.user_item_id = ui.id
      join variants v   on v.id = ui.variant_id
      join products p   on p.id = v.product_id
      join categories c on c.id = p.category_id
     where c.is_anchor
       and ui.deleted_at is null
       and ui.status <> 'want_to_try';

comment on view user_shade_anchor is
    'Worn anchor shades with a fit. Excludes want_to_try: a never-worn product is not shade evidence (GLO-145). The item_fits row survives a status change; this view is what stops counting it.';

-- ---------------------------------------------------------------------------
-- Retiring the workaround.
--
-- anchor_badge() (0025) carried `ui.status <> 'want_to_try'` explicitly, with a
-- comment saying it was compensating for this view rather than inheriting from
-- it. That was the right call while the view was wrong and is the wrong call
-- now: a filter duplicated in a caller is a filter that will disagree with its
-- source eventually. The join to user_items existed ONLY to reach `status` and
-- `deleted_at`, both of which the view now settles, so the whole join goes.
--
-- The second consumer had no workaround at all, which is the actual argument
-- for fixing this at the source: refresh_user_facts() (0011) counts
-- `user_shade_anchor` rows into user_facts.anchors_n, and has been counting
-- never-worn shades as anchors in analytics this whole time. It needed no edit
-- — it reads the view, so it is fixed by this file.
-- ---------------------------------------------------------------------------
create or replace function anchor_badge(p_user uuid)
returns text language sql stable security definer set search_path = public as $$
    select b.name || ' ' || v.shade_code
      from user_shade_anchor a
      join variants v on v.id = a.variant_id
      join products p on p.id = v.product_id
      join brands b   on b.id = p.brand_id
     where a.user_id = p_user
       and v.shade_code is not null
     order by a.captured_at desc
     limit 1;
$$;
