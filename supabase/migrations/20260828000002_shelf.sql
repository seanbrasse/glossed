-- 0002 · Shelf: profiles, user items, chips, fits. tech/01 §1.2, domain.md.
-- Every table here is user-scoped: RLS owner-only, isolation-tested.

create type item_status as enum ('want_to_try', 'own', 'finished', 'repurchased');
create type fit_enum as enum ('just_right', 'too_light', 'too_dark', 'too_pink', 'too_yellow', 'too_orange');

create table profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    display_name text,
    avatar_seed text,
    timezone text not null default 'America/New_York',
    birth_year_month char(7) not null, -- 'YYYY-MM'; full birthday validated at signup then discarded (domain.md §6)
    domains domain_enum[] not null default '{}',
    skin_type text check (skin_type in ('oily', 'dry', 'combo', 'sensitive')),
    concerns text[] not null default '{}',
    tone_band int check (tone_band between 1 and 10), -- internal band; anchors always overwrite for matching
    hair_pattern text check (hair_pattern ~ '^[1-4][a-c]$'),
    climate text,
    brand_affinities text[] not null default '{}',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint birth_year_month_shape check (birth_year_month ~ '^\d{4}-(0[1-9]|1[0-2])$')
);

create table user_items (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    variant_id uuid not null references variants (id),
    status item_status not null default 'own',
    acquired_on date,
    started_on date, -- drives wear-in gating against categories.wear_in_days
    note text,
    cutout_r2_key text, -- the user's own cutout: personal, never canonical
    like_state smallint check (like_state between -1 and 1), -- pre-ranking signal
    client_id uuid not null unique, -- idempotency: double-taps are no-ops
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    unique (user_id, variant_id)
);
create index user_items_user on user_items (user_id) where deleted_at is null;

create table item_chips (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    user_item_id uuid not null references user_items (id) on delete cascade,
    experience_chip_id uuid not null references experience_chips (id),
    week int check (week >= 1), -- required for skincare reactions; enforced in service + aggregate filters
    freetext text, -- "other" write-ins → weekly vocab review
    created_at timestamptz not null default now(),
    unique (user_item_id, experience_chip_id)
);
create index item_chips_user on item_chips (user_id);

create table item_fits (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    user_item_id uuid not null unique references user_items (id) on delete cascade,
    fit fit_enum not null,
    season text,
    captured_at timestamptz not null default now()
);
create index item_fits_user on item_fits (user_id);

-- The PRD §05 schema falls out of log data: anchors are a VIEW, never an entry flow.
-- security_invoker so RLS on the underlying tables applies to the caller.
create view user_shade_anchor with (security_invoker = true) as
select ui.user_id, ui.variant_id, f.fit, f.season, f.captured_at
from user_items ui
join item_fits f on f.user_item_id = ui.id
join variants v on v.id = ui.variant_id
join products p on p.id = v.product_id
join categories c on c.id = p.category_id
where c.is_anchor and ui.deleted_at is null;

-- ---------------------------------------------------------------------------
-- RLS: owner-only on every verb. Aggregation reads happen via service role
-- into identifier-free agg tables (migration 0004), never via these policies.
-- ---------------------------------------------------------------------------
alter table profiles enable row level security;
alter table user_items enable row level security;
alter table item_chips enable row level security;
alter table item_fits enable row level security;

create policy profiles_own on profiles for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

create policy user_items_own on user_items for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

create policy item_chips_own on item_chips for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (
        user_id = (select auth.uid())
        and exists (select 1 from user_items ui where ui.id = user_item_id and ui.user_id = (select auth.uid()))
    );

create policy item_fits_own on item_fits for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (
        user_id = (select auth.uid())
        and exists (select 1 from user_items ui where ui.id = user_item_id and ui.user_id = (select auth.uid()))
    );
