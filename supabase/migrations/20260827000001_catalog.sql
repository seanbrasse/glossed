-- 0001 · Catalog: brands, categories, products, variants, chips vocabulary.
-- Vocabulary matches docs/domain.md exactly. Public read; writes via service role
-- (ingest jobs) except personal-scope product creation. tech/01 §1.1.

create extension if not exists pg_trgm;

create type domain_enum as enum ('makeup', 'skincare', 'haircare', 'fragrance');
create type catalog_scope as enum ('personal', 'submitted', 'canonical');
create type variant_kind as enum ('shade', 'formulation', 'concentration', 'default');
create type image_kind as enum ('catalog', 'typographic');
create type chip_valence as enum ('like', 'dislike');

create table brands (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    normalized_name text not null unique,
    aliases text[] not null default '{}',
    source text not null default 'seed',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index brands_name_trgm on brands using gin (normalized_name gin_trgm_ops);

create table categories (
    id uuid primary key default gen_random_uuid(),
    domain domain_enum not null,
    parent_id uuid references categories (id),
    slug text not null unique,
    label text not null,
    wear_in_days int not null default 0,
    is_anchor boolean not null default false,
    rank_unlock_min int not null default 3,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table products (
    id uuid primary key default gen_random_uuid(),
    brand_id uuid not null references brands (id),
    category_id uuid not null references categories (id),
    domain domain_enum not null,
    name text not null,
    normalized_name text not null,
    benefit_line text,
    scope catalog_scope not null default 'canonical',
    created_by uuid references auth.users (id),
    inci_raw text,
    inci_parsed jsonb,
    forked_from uuid references products (id),
    merged_into uuid references products (id),
    delisted_at timestamptz,
    source text not null default 'seed',
    last_verified timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    -- personal/submitted products must carry their creator; canonical never needs one
    constraint personal_has_creator check (scope = 'canonical' or created_by is not null)
);
create index products_name_trgm on products using gin (normalized_name gin_trgm_ops);
create index products_brand on products (brand_id);
create index products_category on products (category_id);
create index products_fts on products using gin (to_tsvector('simple', name || ' ' || normalized_name));

create table variants (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references products (id),
    kind variant_kind not null default 'default',
    shade_code text,
    shade_hex text,
    size_ml numeric,
    strength_pct numeric,
    gtin text unique,
    height_mm numeric,
    width_mm numeric,
    price_cents int,
    currency text default 'USD',
    availability text,
    source text not null default 'seed',
    last_verified timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index variants_product on variants (product_id);

create table variant_images (
    id uuid primary key default gen_random_uuid(),
    variant_id uuid not null references variants (id),
    kind image_kind not null default 'catalog',
    r2_key text not null,
    width int,
    height int,
    image_source text,
    last_fetched timestamptz,
    created_at timestamptz not null default now()
);
create index variant_images_variant on variant_images (variant_id);

-- Attribute chips: derived only from structured fields, never marketing copy.
create table attribute_chips (
    id uuid primary key default gen_random_uuid(),
    domain domain_enum,
    slug text not null unique,
    label text not null,
    created_at timestamptz not null default now()
);

create table product_attributes (
    product_id uuid not null references products (id),
    attribute_chip_id uuid not null references attribute_chips (id),
    source text not null,
    primary key (product_id, attribute_chip_id)
);

-- Experience chips: fixed launch vocabulary + weekly-promoted write-ins.
create table experience_chips (
    id uuid primary key default gen_random_uuid(),
    domain domain_enum not null,
    category_id uuid references categories (id),
    slug text not null unique,
    label text not null,
    valence chip_valence not null,
    created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- RLS. Personal-scope isolation is structural: a personal product physically
-- cannot appear in another user's reads (ADR 0003, domain.md §3.1).
-- ---------------------------------------------------------------------------
alter table brands enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table variants enable row level security;
alter table variant_images enable row level security;
alter table attribute_chips enable row level security;
alter table product_attributes enable row level security;
alter table experience_chips enable row level security;

create policy brands_read on brands for select using (true);
create policy categories_read on categories for select using (true);
create policy attribute_chips_read on attribute_chips for select using (true);
create policy experience_chips_read on experience_chips for select using (true);
create policy product_attributes_read on product_attributes for select using (true);

create policy products_read on products for select
    using (scope = 'canonical' or created_by = (select auth.uid()));

-- Users create products only in personal scope, owned by themselves.
create policy products_create_personal on products for insert
    to authenticated
    with check (scope = 'personal' and created_by = (select auth.uid()));

-- Owners may edit their personal products; canonical rows are service-role only.
create policy products_update_own_personal on products for update
    to authenticated
    using (scope = 'personal' and created_by = (select auth.uid()))
    with check (scope = 'personal' and created_by = (select auth.uid()));

create policy variants_read on variants for select
    using (exists (
        select 1 from products p
        where p.id = product_id
          and (p.scope = 'canonical' or p.created_by = (select auth.uid()))
    ));

create policy variants_create_for_own_personal on variants for insert
    to authenticated
    with check (exists (
        select 1 from products p
        where p.id = product_id
          and p.scope = 'personal'
          and p.created_by = (select auth.uid())
    ));

create policy variant_images_read on variant_images for select
    using (exists (
        select 1 from variants v join products p on p.id = v.product_id
        where v.id = variant_id
          and (p.scope = 'canonical' or p.created_by = (select auth.uid()))
    ));
