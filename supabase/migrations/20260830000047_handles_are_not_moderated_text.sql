-- GLO-191: a handle is an identifier, not moderated text.
--
-- `public_texts` was built for text that can be edited: it renders the
-- previously approved body while a new one is pending, which presumes a
-- previous version and a next edit. A bio has both. A handle has neither —
-- 0023 says so itself: "There is no handle-CHANGE flow in 1.5, which is
-- precisely why there is no release/cooldown table: you cannot free a handle,
-- so nobody can snipe one."
--
-- So the moderation row was a no-op. **No code path does anything with a
-- rejected handle** — there is no release, rename or re-claim to trigger. And
-- the handle renders publicly the moment it is claimed regardless, because
-- `public_profile` selects `h.handle` straight from `handles`, unfiltered by
-- state (GLO-187, now recorded in tech/02 §3.2).
--
-- What replaces it is the synchronous half that already exists and is the
-- majority of what a handle filter is for: shape, uniqueness,
-- `reserved_handles`, and brand impersonation across every row in `brands`.
-- The explicit/slur pass is the remaining piece and is deliberately NOT in
-- this migration — an LLM call belongs in an Edge Function, so it lands
-- separately. Report-and-block is the after-the-fact remedy and is already
-- built (GLO-142).

-- Unchanged except for the removed insert and the comment that was false.
create or replace function claim_handle(p_handle text)
returns text language plpgsql security definer set search_path = public as $$
declare
    v_user uuid := (select auth.uid());
    v_h    text := lower(trim(p_handle));
begin
    if v_user is null then
        raise exception 'sign in to claim a handle' using errcode = 'insufficient_privilege';
    end if;
    -- A handle IS the public identity; there is nothing for a locked-private
    -- account to claim.
    if is_minor_user(v_user) then
        raise exception 'handles are a public identity' using errcode = 'check_violation';
    end if;
    if exists (select 1 from reserved_handles where handle = v_h) then
        raise exception 'handle reserved' using errcode = 'check_violation';
    end if;
    -- Impersonation rides data we already have: 497 brands and growing, so this
    -- check strengthens for free as the catalog grows.
    if exists (select 1 from brands where normalized_name = v_h) then
        raise exception 'handle matches a brand name' using errcode = 'check_violation';
    end if;

    -- Every check above ran in this transaction. A handle that reaches this
    -- line is claimed and live; there is no later gate, and nothing downstream
    -- pretends otherwise any more.
    insert into handles (user_id, handle) values (v_user, v_h);

    return v_h;
end $$;

-- The rows already written carry no information: `body` is the handle, which
-- `handles` holds as the unique key, and `state` was never read by anything.
-- Deleting them is not data loss — it is removing records that assert a
-- moderation outcome nobody honours. Leaving them would keep the lie readable
-- through `myPublicTexts()`.
delete from public_texts where kind = 'handle';

-- The enum value stays. Postgres cannot drop an enum member, and a `handle`
-- kind that nothing writes is harmless where a half-dropped type would not be.
comment on type public_text_kind is
    'Moderated text kinds. `handle` is legacy and is no longer written: a handle '
    'is an identifier checked synchronously at claim time (GLO-191), not text '
    'reviewed afterwards. `linked_social` is written but not classified '
    '(GLO-189) until a surface renders one.';
