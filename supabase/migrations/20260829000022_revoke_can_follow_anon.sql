-- 0022 · can_follow should never have been reachable by anon. GLO-116 follow-up.
--
-- Found by the Supabase security advisors after 0020/0021 reached hosted.
--
-- 0020 granted can_follow(uuid) to `authenticated` but never revoked it from
-- `anon` — and Supabase's `alter default privileges in schema public grant
-- execute on functions to anon, authenticated, service_role` had already given
-- anon a DIRECT grant. Granting to authenticated does not remove that. This is
-- the same trap 0020 documented for revokes, hit from the other direction:
-- there, a revoke that named too little; here, a grant that implied a revoke it
-- never performed.
--
-- Impact is small — for anon, auth.uid() is null, so `p_target <> null` makes
-- the whole predicate null and the function answers nothing useful. But an
-- unintended grant on a SECURITY DEFINER function is not something to leave
-- standing because today's version of it happens to be harmless.
--
-- The rule this encodes, and the one every future 1.5 migration should follow:
-- state the FULL intended ACL for each function — revoke from everyone, then
-- grant to exactly the roles that need it. Never rely on a grant to imply the
-- absence of another.

revoke execute on function can_follow(uuid) from public, anon;

-- Restated so the intended end state is visible in one place rather than
-- spread across two migrations.
grant execute on function can_follow(uuid) to authenticated;
