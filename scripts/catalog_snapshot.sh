#!/usr/bin/env bash
# GLO-223 — snapshot / restore the catalog around a `supabase db reset`.
#
# Sean's ruling (Aug 30): user data is expendable at this stage, the catalog is
# not. The catalog is NOT in seed.sql — it is ~22,600 rows put there by the
# seven import scripts in HANDOFF §9, which cost ~50 minutes and need network
# plus the service-role key. A reset drops all of it and gives back four
# fixture products.
#
# HANDOFF §9 already warned about that cost, and the warning did not stop a
# lane from nearly resetting anyway. So this is the warning made mechanical.
set -euo pipefail

CONTAINER="${GLOSSED_DB_CONTAINER:-supabase_db_glossed}"
SNAPSHOT="${GLOSSED_CATALOG_SNAPSHOT:-supabase/.catalog-snapshot.sql}"

# Dependency order: brands/categories before products, products before
# variants, variants before variant_images.
#
# pg_dump warns that `categories` and `products` carry CIRCULAR foreign keys —
# categories.parent_id, products.forked_from, products.merged_into all point at
# their own table — and that a --data-only dump "might not be restorable"
# without --disable-triggers. Table ordering cannot fix a self-reference.
#
# Verified empirically rather than assumed: truncate + restore inside a rolled
# back transaction returns 3206 products / 9019 variants / 7625 images / 497
# brands, clean. It works because those self-referencing columns are null for
# every row today. If a future merge populates products.merged_into, the
# restore becomes row-order dependent — add --disable-triggers here if it ever
# fails on an FK, which local can do because it runs as postgres.
TABLES=(
    brands
    categories
    experience_chips
    attribute_chips
    products
    variants
    variant_images
    merge_candidates
)

die() { printf '%s\n' "$*" >&2; exit 1; }

docker exec "$CONTAINER" true 2>/dev/null \
    || die "no database container '$CONTAINER' — is \`supabase start\` running?"

psql_q() { docker exec -i "$CONTAINER" psql -U postgres -tA -c "$1"; }

catalog_rows() {
    local total=0 n
    for t in "${TABLES[@]}"; do
        n=$(psql_q "select count(*) from $t" 2>/dev/null || echo 0)
        total=$((total + n))
    done
    printf '%s' "$total"
}

case "${1:-}" in
save)
    # count(*), never pg_stat_user_tables.n_live_tup — that is an autovacuum
    # estimate, it is stale after a bulk load, and on this database it reports
    # ZERO products. It fails in the direction that makes the catalog look
    # worthless, which is the direction that gets it deleted.
    rows=$(catalog_rows)
    [ "$rows" -gt 0 ] || die "refusing to snapshot: the catalog is already empty (0 rows). \
Restore it with HANDOFF §9's scripts first, or you would overwrite a good snapshot with nothing."

    mkdir -p "$(dirname "$SNAPSHOT")"
    args=(); for t in "${TABLES[@]}"; do args+=(-t "public.$t"); done
    docker exec "$CONTAINER" pg_dump -U postgres --data-only --no-owner --no-privileges \
        "${args[@]}" postgres > "$SNAPSHOT.tmp"

    # Only replace a good snapshot once the new one is written whole.
    mv "$SNAPSHOT.tmp" "$SNAPSHOT"
    printf 'catalog snapshot: %s rows -> %s (%s)\n' \
        "$rows" "$SNAPSHOT" "$(du -h "$SNAPSHOT" | cut -f1)"
    ;;
load)
    [ -f "$SNAPSHOT" ] || die "no snapshot at $SNAPSHOT — run 'make catalog-snapshot' before resetting, \
or rebuild from HANDOFF §9's seven scripts (~50 min)."

    before=$(catalog_rows)
    # -1 wraps the whole restore in ONE transaction: a failure halfway leaves
    # the catalog as it was rather than half-populated, which is the state
    # nobody would notice.
    docker exec -i "$CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -q -1 < "$SNAPSHOT"
    after=$(catalog_rows)
    printf 'catalog restored: %s -> %s rows\n' "$before" "$after"
    [ "$after" -gt "$before" ] || die "restore ran but the row count did not grow — check the snapshot."
    ;;
count)
    printf '%s\n' "$(catalog_rows)"
    ;;
*)
    die "usage: $0 {save|load|count}"
    ;;
esac
