-- 0051 · Routine cadence: when in the day, and how often. GLO-265, GLO-210.
--
-- `routine_slot` folded two independent axes into four words, so "every 3 days"
-- and "bi-weekly" were inexpressible and more enum values were the only growth
-- path. This splits the axes. WASH DAY IS NOT A FREQUENCY — it is an event that
-- happens when it happens, so it lives in its own column with its own lookup
-- table rather than as a fifth value in a list of intervals.
--
-- CADENCE IS A LABEL. Nothing reads it to remind, schedule or nudge, and
-- nothing in this migration starts. APNs is Phase 3 (GLO-39); a scheduling
-- field that nothing schedules is how a notification system nobody asked for
-- gets built by accident.

create type routine_cadence as enum
    ('daily', 'every_n_days', 'weekdays', 'every_n_weeks', 'event');

-- GLO-210: the composer says "am/pm", browse says "morning/evening", and that
-- is a COPY divergence with one legal home already (DataKit.RoutineSlot.label).
-- The schema's part in settling it is to introduce no third vocabulary: these
-- are the existing wire words, plus `both`, which `slot` could not say.
create type routine_time_of_day as enum ('am', 'pm', 'both');

-- Events are data, not type values: adding "gym day" should be an insert, not
-- a migration. This is the answer to "adding enum values does not scale".
create table routine_events (
    key        text primary key,
    label      text not null,
    created_at timestamptz not null default now()
);

insert into routine_events (key, label) values ('wash_day', 'wash day');

alter table routine_events enable row level security;
create policy routine_events_read on routine_events for select using (true);
revoke insert, update, delete on table routine_events from anon, authenticated;

alter table routines
    add column cadence     routine_cadence,
    add column interval_n  int,
    add column weekdays    smallint[],
    add column time_of_day routine_time_of_day,
    add column event_key   text references routine_events (key);

-- Carrying the four live values across. `weekly` becomes every_n_weeks with
-- n = 1, which is what it always meant and could never say.
update routines set
    cadence     = (case slot when 'wash_day' then 'event'
                             when 'weekly'   then 'every_n_weeks'
                             else 'daily' end)::routine_cadence,
    interval_n  = case slot when 'weekly'   then 1 else null end,
    time_of_day = (case slot when 'am' then 'am'
                             when 'pm' then 'pm' end)::routine_time_of_day,
    event_key   = case slot when 'wash_day' then 'wash_day' else null end;

-- NOT NULL but deliberately NO DEFAULT: the trigger below seeds `cadence` from
-- `slot` precisely when a writer left it null, and a column default would fill
-- it in first and silence that branch for every legacy write. NOT NULL is
-- checked after BEFORE triggers, so the trigger always gets its turn.
alter table routines alter column cadence set not null;

-- A discriminated union, enforced. Without this the columns are four
-- independent fields that can describe a routine which is every 3 days AND on
-- Tuesdays AND a wash day. Weekdays are ISO (1 = Monday .. 7 = Sunday), so they
-- match extract(isodow) rather than needing a translation nobody remembers.
alter table routines add constraint routines_cadence_shape check (
    case cadence
        when 'daily'         then interval_n is null and weekdays is null and event_key is null
        when 'every_n_days'  then interval_n >= 1    and weekdays is null and event_key is null
        when 'every_n_weeks' then interval_n >= 1    and weekdays is null and event_key is null
        when 'weekdays'      then interval_n is null and event_key is null
                                  and weekdays <@ array[1,2,3,4,5,6,7]::smallint[]
                                  and array_length(weekdays, 1) between 1 and 7
        when 'event'         then interval_n is null and weekdays is null and event_key is not null
    end
);

-- `slot` STAYS, and is demoted to a derived projection rather than kept as a
-- second source of truth — the outcome GLO-265 names as the thing to avoid.
-- It cannot simply be dropped: browse_routines takes it as a parameter and
-- DataKit's RoutineSlot is frozen, so removing it breaks a lane that cannot
-- edit itself. It also cannot become a GENERATED column, because
-- RoutinesRepository WRITES it and a generated column rejects that.
--
-- So the trigger reconciles both directions. A writer that only knows `slot`
-- (today's client) seeds the cadence from it; a writer that sets the cadence
-- wins, and `slot` is re-derived from the cadence either way. The two cannot
-- disagree because only one of them is ever authored.
create or replace function reconcile_routine_slot()
returns trigger language plpgsql as $$
declare
    v_seed boolean;
begin
    if tg_op = 'INSERT' then
        v_seed := new.cadence is null;
    else
        -- A slot-only writer changed the projection; the cadence columns it
        -- cannot see must follow it rather than silently overrule it.
        v_seed := new.slot is distinct from old.slot
              and new.cadence is not distinct from old.cadence;
    end if;

    if v_seed then
        new.cadence     := (case new.slot when 'wash_day' then 'event'
                                          when 'weekly'   then 'every_n_weeks'
                                          else 'daily' end)::routine_cadence;
        new.interval_n  := case new.slot when 'weekly'   then 1 else null end;
        new.time_of_day := (case new.slot when 'am' then 'am'
                                          when 'pm' then 'pm' end)::routine_time_of_day;
        new.event_key   := case new.slot when 'wash_day' then 'wash_day' else null end;
    end if;

    -- Lossy on purpose: four words cannot hold five cadences crossed with three
    -- times of day. Browse buckets by this; the cadence columns are the truth.
    new.slot := case
        when new.cadence = 'event'                            then 'wash_day'
        when new.cadence in ('weekdays', 'every_n_weeks')     then 'weekly'
        when new.time_of_day = 'pm'                           then 'pm'
        else 'am' end::routine_slot;
    return new;
end $$;

create trigger routines_reconcile_slot before insert or update on routines
    for each row execute function reconcile_routine_slot();

comment on type routine_time_of_day is
    'Identifiers, not copy. The words a user reads have ONE home (DataKit.RoutineSlot.label); GLO-210 is the choice between "am/pm" and "morning/evening" and it is not settled here.';

comment on column routines.slot is
    'DERIVED PROJECTION, maintained by routines_reconcile_slot — not a second source of truth. The cadence columns are authoritative; slot is the four-word bucket browse_routines still filters on. Lossy by construction (GLO-265).';

comment on constraint routines_cadence_shape on routines is
    'A discriminated union: each cadence permits exactly its own operand. Wash day is an EVENT — event_key, never a frequency.';

comment on table routine_events is
    'Event-driven cadences, as data. A new event is an insert, not a migration and not an enum value (GLO-265).';
