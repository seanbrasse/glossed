-- 0011 · First-party analytics: events, rollups, user_facts. GLO-21 PR 1;
-- docs/tech/06 §§1–2, 4.
--
-- The posture, enforced structurally rather than by convention:
--
--   - Events carry identifiers, not values. The client's compiler-checked
--     enum is the first wall; this schema is the second: props is jsonb but
--     nothing user-facing can write it — there are NO user grants on any
--     table here. Writes arrive only through track_ingest (service role).
--   - Nothing in `events` is readable by the rec pipeline. Rec RPCs run as
--     definer functions owned by roles with no grants here; there is no
--     select policy for authenticated at all.
--   - Raw events live 12 months then roll up and drop — monthly partitions
--     make the drop a detach, not a delete.

create extension if not exists pg_cron;

create table events (
    id bigint generated always as identity,
    -- Client-generated per event; a retried batch re-sends the same id and
    -- the insert's on-conflict makes it a no-op. The partition key has to be
    -- part of any unique constraint, and a retry re-sends the same ts too.
    client_id uuid not null,
    user_id uuid,          -- null for pre-signup onboarding
    anon_id uuid,          -- links the pre-signup funnel to the account after signup
    name text not null,
    props jsonb not null default '{}',
    screen text,
    app_version text,
    os_version text,
    ts timestamptz not null,
    primary key (id, ts),
    unique (client_id, ts)
) partition by range (ts);

create index events_name_ts on events (name, ts);
create index events_user_ts on events (user_id, ts) where user_id is not null;

-- One month per partition. Creating them is idempotent so the monthly cron
-- job and a manual catch-up cannot collide.
create or replace function ensure_events_partition(p_month date)
returns void language plpgsql security definer set search_path = public as $$
declare
    v_start date := date_trunc('month', p_month)::date;
    v_end date := (v_start + interval '1 month')::date;
    v_name text := 'events_' || to_char(v_start, 'YYYY_MM');
begin
    execute format(
        'create table if not exists %I partition of events for values from (%L) to (%L)',
        v_name, v_start, v_end);
end $$;

select ensure_events_partition(current_date);
select ensure_events_partition((current_date + interval '1 month')::date);

-- Retention: partitions older than 12 months detach and drop, whole.
create or replace function drop_expired_event_partitions()
returns void language plpgsql security definer set search_path = public as $$
declare
    v_cutoff date := date_trunc('month', current_date - interval '12 months')::date;
    v_partition record;
begin
    for v_partition in
        select c.relname
        from pg_inherits i
        join pg_class c on c.oid = i.inhrelid
        join pg_class p on p.oid = i.inhparent
        where p.relname = 'events'
          and c.relname ~ '^events_\d{4}_\d{2}$'
          and to_date(substring(c.relname from 8), 'YYYY_MM') < v_cutoff
    loop
        execute format('alter table events detach partition %I', v_partition.relname);
        execute format('drop table %I', v_partition.relname);
    end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Rollups: the dashboard reads these, never raw events.
-- ---------------------------------------------------------------------------
create table event_rollups_daily (
    day date not null,
    name text not null,
    cohort_key text not null default 'all',
    n int not null,
    users int not null,
    primary key (day, name, cohort_key)
);

create or replace function refresh_event_rollups(p_day date default (current_date - 1))
returns void language sql security definer set search_path = public as $$
    insert into event_rollups_daily (day, name, cohort_key, n, users)
    select p_day, name, 'all', count(*), count(distinct coalesce(user_id, anon_id))
    from events
    where ts >= p_day and ts < p_day + 1
    group by name
    on conflict (day, name, cohort_key)
        do update set n = excluded.n, users = excluded.users;
$$;

-- ---------------------------------------------------------------------------
-- user_facts: the "who is our user base" snapshot. Every analysis is
-- events ⋈ user_facts; the join happens here, in our own Postgres, because
-- body facts are Regulated-class and never leave (tech/06 §1).
-- ---------------------------------------------------------------------------
create table user_facts (
    user_id uuid primary key references auth.users (id) on delete cascade,
    signup_cohort_week date,
    age_bracket text,      -- 13–17 · 18–24 · 25–34 · 35–44 · 45+; brackets only, ever
    domains domain_enum[],
    skin_type text,
    tone_band int,
    hair_pattern text,
    anchor_count int not null default 0,
    shelf_size int not null default 0,
    ranked_lists int not null default 0,
    two_domain boolean not null default false,
    minor boolean not null default false,
    last_active_day date,
    refreshed_at timestamptz not null default now()
);

create or replace function age_bracket(p_birth char(7), p_on date default current_date)
returns text language sql immutable parallel safe set search_path = public as $$
    select case
        when age < 18 then '13-17'
        when age < 25 then '18-24'
        when age < 35 then '25-34'
        when age < 45 then '35-44'
        else '45+'
    end
    from (select extract(year from age(p_on, to_date(p_birth || '-01', 'YYYY-MM-DD')))::int as age) a;
$$;

create or replace function refresh_user_facts()
returns void language sql security definer set search_path = public as $$
    insert into user_facts (
        user_id, signup_cohort_week, age_bracket, domains, skin_type, tone_band,
        hair_pattern, anchor_count, shelf_size, ranked_lists, two_domain, minor,
        last_active_day, refreshed_at
    )
    select
        p.user_id,
        date_trunc('week', p.created_at)::date,
        age_bracket(p.birth_year_month),
        p.domains,
        p.skin_type,
        p.tone_band,
        p.hair_pattern,
        (select count(*)::int from user_shade_anchor a where a.user_id = p.user_id),
        (select count(*)::int from user_items ui where ui.user_id = p.user_id and ui.deleted_at is null),
        (select count(distinct (rp.category_id, rp.scope_key))::int
           from rank_positions rp where rp.user_id = p.user_id),
        coalesce(array_length(p.domains, 1), 0) >= 2,
        age_bracket(p.birth_year_month) = '13-17',
        (select max(e.ts)::date from events e where e.user_id = p.user_id),
        now()
    from profiles p
    on conflict (user_id) do update set
        age_bracket = excluded.age_bracket,
        domains = excluded.domains,
        skin_type = excluded.skin_type,
        tone_band = excluded.tone_band,
        hair_pattern = excluded.hair_pattern,
        anchor_count = excluded.anchor_count,
        shelf_size = excluded.shelf_size,
        ranked_lists = excluded.ranked_lists,
        two_domain = excluded.two_domain,
        minor = excluded.minor,
        last_active_day = excluded.last_active_day,
        refreshed_at = excluded.refreshed_at;
$$;

-- ---------------------------------------------------------------------------
-- RLS: enabled, and deliberately no policies for any user role. The ingest
-- and the refreshes run as service/definer; Metabase gets its own read-only
-- role later (tech/06 §5), granted explicitly then.
-- ---------------------------------------------------------------------------
alter table events enable row level security;
alter table event_rollups_daily enable row level security;
alter table user_facts enable row level security;

-- RLS-with-no-policy still lets a select return zero rows quietly; "no
-- grants" should mean the query *fails*, so the default table grants go too.
-- A silent empty result reads as "no data"; a permission error reads as what
-- it is.
revoke all on events, event_rollups_daily, user_facts from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The clock. Off the :00/:30 marks deliberately.
-- ---------------------------------------------------------------------------
select cron.schedule('events-partition-ahead', '17 2 1 * *',
    $$select ensure_events_partition((current_date + interval '1 month')::date)$$);
select cron.schedule('events-retention', '23 2 1 * *',
    $$select drop_expired_event_partitions()$$);
select cron.schedule('event-rollups-nightly', '41 3 * * *',
    $$select refresh_event_rollups()$$);
select cron.schedule('user-facts-nightly', '52 3 * * *',
    $$select refresh_user_facts()$$);
