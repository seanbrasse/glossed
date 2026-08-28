-- 0009 · Fit goes multi-axis. GLO-67, decided Aug 28: the kit wins.
--
-- The kit's FitControl holds one answer per axis — lightness and undertone are
-- independent, and a shade can miss on both. The schema stored one fit per
-- item, so a user whose foundation is both too light and too pink could only
-- say half of it, and the shade evidence was built on whichever half they
-- picked. PRD §05's "a miss is a bounded anchor" wants both bounds.

-- Which axis an answer sits on. A generated column, so the rule cannot drift
-- from the data and the uniqueness below is enforceable by the database
-- rather than by convention.
create or replace function fit_axis(p_fit fit_enum) returns text
language sql immutable parallel safe set search_path = public as $$
    select case p_fit
        when 'just_right' then 'just_right'
        when 'too_light'  then 'depth'
        when 'too_dark'   then 'depth'
        else 'undertone'  -- too_pink, too_yellow, too_orange
    end;
$$;

alter table item_fits drop constraint item_fits_user_item_id_key;
alter table item_fits add column axis text generated always as (fit_axis(fit)) stored;
-- One answer per axis, per item. Two depth answers ("too light" and "too
-- dark") were never a coherent statement; two axes are.
alter table item_fits add constraint item_fits_one_per_axis unique (user_item_id, axis);

-- The whole capture in one call, because the kit's rules are about the *set*:
-- `just right` is exclusive, everything else composes one-per-axis. Two
-- upserts with a window between them could leave "just right + too pink" on
-- disk, which is not a state the control can express.
--
-- Security INVOKER — RLS on item_fits already proves ownership of every row;
-- this adds atomicity and the set rule, not a second permission model
-- (the apply_face_off_session precedent).
create or replace function capture_fit(
    p_user_item_id uuid,
    p_fits fit_enum[],
    p_season text default null
) returns void
language plpgsql as $$
declare
    v_user uuid := auth.uid();
begin
    if v_user is null then
        raise exception 'not authenticated' using errcode = '42501';
    end if;
    if p_fits is null or array_length(p_fits, 1) is null then
        raise exception 'a capture names at least one fit' using errcode = '22023';
    end if;
    if 'just_right' = any (p_fits) and array_length(p_fits, 1) > 1 then
        raise exception 'just right stands alone' using errcode = '23514';
    end if;
    -- One answer per axis. The unique constraint would catch this on insert,
    -- but naming the rule beats surfacing a constraint violation.
    if (select count(distinct fit_axis(f)) from unnest(p_fits) f) <> array_length(p_fits, 1) then
        raise exception 'one answer per axis' using errcode = '23514';
    end if;

    -- The capture replaces the answer wholesale: axes the user cleared go.
    delete from item_fits where user_item_id = p_user_item_id and user_id = v_user;
    insert into item_fits (user_id, user_item_id, fit, season)
    select v_user, p_user_item_id, f, p_season from unnest(p_fits) f;
end
$$;
grant execute on function capture_fit(uuid, fit_enum[], text) to authenticated;
