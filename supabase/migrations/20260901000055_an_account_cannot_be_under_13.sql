-- The under-13 block stops being a client-side promise. GLO-23.
--
-- PRD §17 makes under-13 a HARD block (COPPA), and until now the only thing
-- enforcing it was `AccountModel.createAccount` — Swift, in the app, on the
-- happy path. A direct PostgREST insert with `birth_year_month = '2020-01'`
-- was accepted by the database without complaint.
--
-- **This is not the same gate as `is_minor`, and the difference is the point.**
-- `is_minor` (0020) answers "is this person under 18", and every 1.5 surface
-- asks it before showing a public identity. It is a VISIBILITY rule, and a
-- 15-year-old is a legitimate user it correctly keeps private. Under-13 is a
-- different question with a different answer: not "show them less" but "there
-- is no account here at all".
--
-- **Why a trigger and not a CHECK constraint.** A CHECK must be immutable, and
-- an age depends on `current_date`, which is not. Postgres refuses the
-- constraint outright; the trigger is the only shape that can express this.
--
-- **What this does and does not stop.** It refuses the `profiles` row. The
-- `auth.users` row is created by GoTrue before the app ever collects a
-- birthday — Apple and phone OTP both authenticate first and ask second — so
-- no gate at this layer can prevent the auth user existing. What it prevents
-- is that user ever becoming a Glossed profile: with no `profiles` row,
-- `is_minor_user` coalesces to true (0020) and every gated surface refuses
-- them. Deleting the orphaned auth user is a retention job, not a constraint,
-- and is deliberately not attempted here.

-- Mirrors `is_minor`'s shape exactly, including the `+ 1 month`, so the two
-- read as one idea at two thresholds.
--
-- That month matters and is a deliberate trade. Only year-and-month is stored
-- (the day never persists — domain.md §6), so a birthday of `2013-09` could be
-- anyone born across that whole month. Adding a month means we refuse until
-- the person has CERTAINLY turned 13 rather than as soon as they MIGHT have.
-- The cost is a real 13-year-old refused for up to a month; the alternative is
-- admitting a real 12-year-old. For a COPPA block that trade only goes one way.
create or replace function public.is_under_13(p_birth character, p_on date default current_date)
returns boolean
language sql
immutable parallel safe
set search_path to 'public'
as $$
    select p_on < (to_date(p_birth || '-01', 'YYYY-MM-DD') + interval '13 years 1 month')::date;
$$;

comment on function public.is_under_13(character, date) is
    'True until the person has certainly turned 13. The account floor (COPPA), '
    'not the privacy gate — that is is_minor.';

create or replace function public.profiles_refuse_under_13()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
    -- The null check cannot fire today — `birth_year_month` is NOT NULL, so
    -- every row reaching this trigger has one. It is written anyway because
    -- the alternative is worse than redundant: if the column were ever
    -- relaxed, `is_under_13(null)` is null, `if null then` does not fire, and
    -- a birthday-less profile would be admitted silently. Stating the
    -- condition makes that outcome a decision rather than an accident.
    if new.birth_year_month is not null and is_under_13(new.birth_year_month) then
        raise exception 'under the minimum age'
            using errcode = 'check_violation',
                  hint = 'glossed has a minimum age of 13';
    end if;
    return new;
end $$;

-- BEFORE INSERT OR UPDATE, and the UPDATE arm is not redundant even though
-- settings stopped offering the birthday as editable (GLO-257): the screen not
-- offering it is a UI fact, and this file is about what the database will
-- accept from anyone at all.
drop trigger if exists profiles_age_floor on profiles;
create trigger profiles_age_floor
    before insert or update of birth_year_month on profiles
    for each row execute function public.profiles_refuse_under_13();
