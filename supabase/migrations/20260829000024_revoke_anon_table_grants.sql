-- 0024 · Take anon's table privileges off every Phase-1.5 table. GLO-120 follow-up.
--
-- Found by checking hosted after 0023, generalising the lesson from GLO-150.
--
-- All eight tables added by 0020 and 0023 arrived with `anon` holding SELECT,
-- INSERT, UPDATE and DELETE, from Supabase's
--   alter default privileges in schema public grant all on tables to anon, authenticated
-- None of them has a single policy naming `anon`, so RLS denies every one of
-- those verbs today and nothing is exploitable.
--
-- That is exactly the problem. It leaves ONE layer where there should be two,
-- and the failure mode is not hypothetical: GLO-150 is the same pattern on the
-- `events` partitions, where RLS happened to be off and the table is readable.
-- Here the privilege is neutralised only by a policy's absence — and the day
-- someone adds a legitimate `to anon` policy for one column, they silently
-- inherit table-wide anon INSERT they never intended to grant.
--
-- Privilege and policy should agree. If anon has no business with a table, say
-- so in both places.
--
-- NOT touched: user_items, collections, collection_items, routines,
-- routine_steps and rank_positions. Those DO carry `to anon` public read
-- policies (0021) and genuinely need the privilege — link cards and web share
-- pages read them unauthenticated.

revoke all on table privacy_scopes  from anon;
revoke all on table follows         from anon;
revoke all on table blocks          from anon;
revoke all on table mutes           from anon;
revoke all on table handles         from anon;
revoke all on table public_texts    from anon;
revoke all on table profile_badges  from anon;

-- reserved_handles has RLS on and ZERO policies by design — it is deny-all to
-- every client role. Enumerating the reserved list is a gift to squatters, so
-- neither anon nor authenticated has any business holding privilege on it.
revoke all on table reserved_handles from anon, authenticated;
