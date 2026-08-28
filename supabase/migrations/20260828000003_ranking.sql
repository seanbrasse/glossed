-- 0003 · Ranking + collections + routines. tech/01 §1.2, §3; ADR 0005.
-- face_offs is the immutable input; rank_positions is the derived output.

create type routine_slot as enum ('am', 'pm', 'weekly', 'wash_day');

create table face_offs (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    category_id uuid not null references categories (id),
    scope_key text not null default 'default', -- scoped buckets (everyday/full_glam/…) are data, not migrations
    winner_item_id uuid not null references user_items (id) on delete cascade,
    loser_item_id uuid not null references user_items (id) on delete cascade,
    skipped boolean not null default false, -- "too close to call" is data too
    client_id uuid not null unique,
    created_at timestamptz not null default now(),
    constraint different_items check (winner_item_id <> loser_item_id)
);
create index face_offs_user_cat on face_offs (user_id, category_id, scope_key);

create table rank_positions (
    user_id uuid not null references auth.users (id) on delete cascade,
    category_id uuid not null references categories (id),
    scope_key text not null default 'default',
    user_item_id uuid not null references user_items (id) on delete cascade,
    position int not null check (position >= 1),
    updated_at timestamptz not null default now(),
    primary key (user_id, category_id, scope_key, user_item_id),
    unique (user_id, category_id, scope_key, position) deferrable initially deferred
);

create table collections (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    title text not null,
    cover_tint text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz
);

create table collection_items (
    collection_id uuid not null references collections (id) on delete cascade,
    user_item_id uuid not null references user_items (id) on delete cascade,
    position int not null default 0,
    primary key (collection_id, user_item_id)
);

create table routines (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    title text not null,
    slot routine_slot not null,
    started_on date,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz
);

create table routine_steps (
    routine_id uuid not null references routines (id) on delete cascade,
    user_item_id uuid not null references user_items (id) on delete cascade,
    position int not null,
    primary key (routine_id, user_item_id)
);

-- ---------------------------------------------------------------------------
-- RLS: owner-only. face_offs is insert-only for users (immutable log —
-- no update/delete policy exists, so those verbs are impossible).
-- ---------------------------------------------------------------------------
alter table face_offs enable row level security;
alter table rank_positions enable row level security;
alter table collections enable row level security;
alter table collection_items enable row level security;
alter table routines enable row level security;
alter table routine_steps enable row level security;

create policy face_offs_read_own on face_offs for select
    to authenticated using (user_id = (select auth.uid()));
create policy face_offs_insert_own on face_offs for insert
    to authenticated
    with check (
        user_id = (select auth.uid())
        and exists (select 1 from user_items w where w.id = winner_item_id and w.user_id = (select auth.uid()))
        and exists (select 1 from user_items l where l.id = loser_item_id and l.user_id = (select auth.uid()))
    );

create policy rank_positions_own on rank_positions for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (
        user_id = (select auth.uid())
        and exists (select 1 from user_items ui where ui.id = user_item_id and ui.user_id = (select auth.uid()))
    );

create policy collections_own on collections for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

create policy collection_items_own on collection_items for all
    to authenticated
    using (exists (select 1 from collections c where c.id = collection_id and c.user_id = (select auth.uid())))
    with check (
        exists (select 1 from collections c where c.id = collection_id and c.user_id = (select auth.uid()))
        and exists (select 1 from user_items ui where ui.id = user_item_id and ui.user_id = (select auth.uid()))
    );

create policy routines_own on routines for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

create policy routine_steps_own on routine_steps for all
    to authenticated
    using (exists (select 1 from routines r where r.id = routine_id and r.user_id = (select auth.uid())))
    with check (
        exists (select 1 from routines r where r.id = routine_id and r.user_id = (select auth.uid()))
        and exists (select 1 from user_items ui where ui.id = user_item_id and ui.user_id = (select auth.uid()))
    );
