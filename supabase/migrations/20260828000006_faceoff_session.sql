-- 0006 · apply_face_off_session. tech/01 §3; ADR 0005.
--
-- One call per ranking session: append the immutable comparison log, then
-- rewrite the derived positions for the lists it touched. Security INVOKER on
-- purpose — RLS already proves every item belongs to the caller, so this
-- function adds atomicity, not a second permission model.
create or replace function apply_face_off_session(p_face_offs jsonb, p_positions jsonb)
returns void
language plpgsql
as $$
declare
    v_user uuid := auth.uid();
begin
    if v_user is null then
        raise exception 'not authenticated' using errcode = '42501';
    end if;

    -- The log is append-only and idempotent: replaying a session after a
    -- dropped connection must not double-count comparisons.
    insert into face_offs (
        user_id, category_id, scope_key, winner_item_id, loser_item_id, skipped, client_id
    )
    select
        v_user,
        (e ->> 'category_id')::uuid,
        coalesce(e ->> 'scope_key', 'default'),
        (e ->> 'winner_item_id')::uuid,
        (e ->> 'loser_item_id')::uuid,
        coalesce((e ->> 'skipped')::boolean, false),
        (e ->> 'client_id')::uuid
    from jsonb_array_elements(coalesce(p_face_offs, '[]'::jsonb)) as e
    on conflict (client_id) do nothing;

    -- Positions are derived, so the touched lists are rebuilt wholesale rather
    -- than patched. Deferred uniqueness lets the delete and insert coexist.
    delete from rank_positions rp
    where rp.user_id = v_user
      and (rp.category_id, rp.scope_key) in (
          select (e ->> 'category_id')::uuid, coalesce(e ->> 'scope_key', 'default')
          from jsonb_array_elements(coalesce(p_positions, '[]'::jsonb)) as e
      );

    insert into rank_positions (user_id, category_id, scope_key, user_item_id, position)
    select
        v_user,
        (e ->> 'category_id')::uuid,
        coalesce(e ->> 'scope_key', 'default'),
        (e ->> 'user_item_id')::uuid,
        (e ->> 'position')::int
    from jsonb_array_elements(coalesce(p_positions, '[]'::jsonb)) as e;
end
$$;
grant execute on function apply_face_off_session(jsonb, jsonb) to authenticated;

-- Skipped comparisons ("too close to call") are data, not absence of data —
-- but they carry no preference, so every consumer must exclude them. This view
-- is the one place that rule lives.
create or replace view scored_face_offs with (security_invoker = true) as
select id, user_id, category_id, scope_key, winner_item_id, loser_item_id, created_at
from face_offs
where not skipped;
