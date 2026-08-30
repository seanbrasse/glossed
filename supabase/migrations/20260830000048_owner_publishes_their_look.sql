-- 0048 · Publishing a look is the owner's decision. GLO-238.
-- 0043 handed `authenticated` a table-wide write grant, so `state` was
-- already client-settable and publishing worked by accident. Sean's ruling
-- (Aug 30) makes it wanted; this says so, narrows it to the one transition,
-- and leaves GLO-26 a one-line close — drop 'public' from the with-check.
-- Nothing screens a look before strangers can read it. That is the decision,
-- not an oversight. `can_post_look()` is untouched: minors still cannot post.

-- A column revoke is a no-op against a standing table grant, so the table
-- grant goes first — otherwise this applies clean and changes nothing.
revoke insert, update on table looks from authenticated;

-- A look is BORN a draft: `state` is absent here, so publishing is always a
-- second, deliberate write. `moderation` and `removed_at` were never meant to
-- be client-reachable and now are not.
grant insert (id, user_id, caption) on table looks to authenticated;

-- `id`/`user_id` are updatable only because PostgREST's upsert re-SETs every
-- payload column on conflict (LooksRepository.saveDraft's retry path); the
-- with-check below still pins user_id to the caller.
grant update (id, user_id, caption, state) on table looks to authenticated;

-- The client's two states. 'pending_review' stays unreachable from here
-- because no reviewer exists to leave it (GLO-189), and 'removed' is the
-- takedown's word — an owner deletes their own row instead.
alter policy looks_update_own on looks
    with check (user_id = (select auth.uid())
            and state in ('draft', 'public'));

-- Ordering is the server's. The feed reads (posted_at desc) where public, so
-- a client-supplied timestamp buys a permanent top slot; `posted_at` is out
-- of the grants above and stamped here instead, for the moderation path too.
create or replace function stamp_look_posted_at()
returns trigger language plpgsql as $$
begin
    if new.state = 'public' and old.state is distinct from 'public' then
        new.posted_at := now();
    elsif new.state is distinct from 'public' and old.state = 'public' then
        new.posted_at := null;
    end if;
    return new;
end $$;

create trigger looks_stamp_posted_at before update of state on looks
    for each row execute function stamp_look_posted_at();

comment on policy looks_update_own on looks is
    'An owner may publish their own look — deliberate and UNMODERATED (GLO-238, Sean''s Aug 30 ruling). GLO-26 closes it by dropping ''public'' from the with-check.';
