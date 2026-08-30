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

# The durable store lives OUTSIDE the repo, and that is the whole point of this
# revision. The first version kept ONE copy at supabase/.catalog-snapshot.sql —
# gitignored, inside a git worktree. On this machine that copy turned out to be
# sitting in one worktree of six, invisible to every other lane. A `git clean`,
# a deleted worktree or a fresh clone and the catalog is a ~50-minute rebuild.
# Durability here comes from where the file lives and how many copies exist.
STORE="${GLOSSED_CATALOG_HOME:-$HOME/.glossed/catalog}"

# Where the pre-GLO-223 snapshot lived. Still read, never written: a machine
# that has one and no store should adopt it rather than silently ignore it.
LEGACY="supabase/.catalog-snapshot.sql"

# Dated generations, newest kept, oldest pruned — so a bad save can never be
# the ONLY save. The regression guard below is the first line of defence and
# this is the second, because a guard can only catch what it can measure.
KEEP="${GLOSSED_CATALOG_KEEP:-5}"

# A snapshot that drops from 22,668 rows to 400 is the failure that matters,
# and the old script could not see it — it refused at zero and nowhere else.
# Anything under this percentage of the newest generation has to be said out
# loud with --allow-shrink.
MIN_PCT="${GLOSSED_CATALOG_MIN_PCT:-90}"

# Dependency order: brands/categories before products, products before
# variants, variants before variant_images.
#
# pg_dump warns that `categories` and `products` carry CIRCULAR foreign keys —
# categories.parent_id, products.forked_from, products.merged_into all point at
# their own table — and that a --data-only dump "might not be restorable".
# Table ordering cannot fix a self-reference.
#
# The old comment here said to reach for --disable-triggers "which local can do
# because it runs as postgres". That was never true and is now measured: this
# container's postgres has usesuper = f, and pg_dump --disable-triggers dies
# with `permission denied: "RI_ConstraintTrigger_..." is a system trigger`.
# `set session_replication_role = replica` IS permitted and does the same job,
# so the restore below uses that instead.
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

# count(*), never pg_stat_user_tables.n_live_tup — that is an autovacuum
# estimate, it is stale after a bulk load, and on this database it reports ZERO
# products against a real 3,206. It fails in the direction that makes the
# catalog look worthless, which is the direction that gets it deleted.
TOTAL=0
COUNTS=()
read_counts() {
    TOTAL=0
    COUNTS=()
    local n
    for t in "${TABLES[@]}"; do
        n=$(psql_q "select count(*) from public.$t" 2>/dev/null || echo 0)
        COUNTS+=("$t=$n")
        TOTAL=$((TOTAL + n))
    done
}

# Generations sort lexically because the name carries the timestamp. The
# trailing `|| true` is load-bearing under `set -o pipefail`: on a machine with
# no store yet, ls exits 1 and would take the whole script down before it could
# say why.
newest() { ls -1 "$STORE"/catalog-*.sql 2>/dev/null | sort | tail -1 || true; }
generations() { ls -1 "$STORE"/catalog-*.sql 2>/dev/null | sort -r || true; }

meta_get() { [ -f "$1" ] && sed -n "s/^$2=//p" "$1" | tail -1; }

case "${1:-}" in
save)
    read_counts
    [ "$TOTAL" -gt 0 ] || die "refusing to snapshot: the catalog is already empty (0 rows). \
Restore it with HANDOFF §9's scripts first, or you would overwrite a good snapshot with nothing."

    prev=$(newest)
    prev_total=$(meta_get "${prev:-}.meta" total || true)
    if [ -n "${prev_total:-}" ] && [ "$prev_total" -gt 0 ] 2>/dev/null; then
        # Integer percentage, no bc: this has to run on a bare machine.
        if [ $((TOTAL * 100)) -lt $((prev_total * MIN_PCT)) ] && [ "${2:-}" != "--allow-shrink" ]; then
            die "refusing to snapshot: $TOTAL rows is under ${MIN_PCT}% of the last snapshot's $prev_total. \
If the catalog really did shrink (a merge, a purge), say so: $0 save --allow-shrink"
        fi
    fi

    mkdir -p "$STORE"
    stamp=$(date -u +%Y%m%d-%H%M%S)
    snap="$STORE/catalog-$stamp.sql"

    # --rows-per-insert + --on-conflict-do-nothing instead of COPY, because the
    # restore lands in a database `supabase db reset` has ALREADY seeded, and
    # seed.sql re-inserts brands/products/variants under FIXED uuids that the
    # snapshot also contains. Plain COPY hits a duplicate key, and since the
    # restore is one transaction that rolls the WHOLE catalog back. This format
    # costs ~16% more on disk (6.5MB -> 7.6MB) and makes restore idempotent.
    # A pg_dump that dies partway must leave NOTHING behind: `set -e` stops the
    # script before the mv below, so the previous generation stays newest, and
    # the trap keeps the half-file from littering the store.
    trap 'rm -f "$snap.tmp" "$snap.tmp.meta"' EXIT
    args=(); for t in "${TABLES[@]}"; do args+=(-t "public.$t"); done
    docker exec "$CONTAINER" pg_dump -U postgres --data-only --no-owner --no-privileges \
        --rows-per-insert=500 --on-conflict-do-nothing "${args[@]}" postgres > "$snap.tmp"

    # What the snapshot contains, so a restore can prove it got it all back.
    {
        printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'git_sha=%s\n' "$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
        printf 'format=inserts\n'
        printf 'total=%s\n' "$TOTAL"
        for c in "${COUNTS[@]}"; do printf 'table.%s\n' "$c"; done
    } > "$snap.tmp.meta"

    # Only publish once both files are written whole — a half-written snapshot
    # that sorts newest is worse than no new snapshot at all.
    mv "$snap.tmp.meta" "$snap.meta"
    mv "$snap.tmp" "$snap"

    # Prune oldest generations, keeping KEEP.
    generations | tail -n +$((KEEP + 1)) | while read -r old; do
        rm -f "$old" "$old.meta"
    done

    printf 'catalog snapshot: %s rows -> %s (%s, %s generations kept)\n' \
        "$TOTAL" "$snap" "$(du -h "$snap" | cut -f1)" \
        "$(generations | wc -l | tr -d ' ')"
    ;;
load)
    snap=$(newest)
    if [ -z "$snap" ] && [ -f "$LEGACY" ]; then
        # Backwards compatibility: a machine that snapshotted before the store
        # existed still has its catalog in the repo tree. Adopt it rather than
        # tell the user there is nothing to restore.
        mkdir -p "$STORE"
        # `stat -f %m` then `date -r <secs>`: BSD date's -r takes seconds, not a
        # filename, so the GNU spelling would silently name every adoption now.
        snap="$STORE/catalog-$(date -u -r "$(stat -f %m "$LEGACY")" +%Y%m%d-%H%M%S).sql"
        cp "$LEGACY" "$snap"
        printf 'created_at=unknown\nformat=copy\nadopted_from=%s\ntotal=0\n' "$LEGACY" > "$snap.meta"
        printf 'adopted the pre-GLO-223 snapshot at %s into %s\n' "$LEGACY" "$STORE"
    fi
    [ -n "$snap" ] || die "no snapshot in $STORE (and no $LEGACY to adopt) — run 'make catalog-snapshot' \
before resetting, or rebuild from HANDOFF §9's seven scripts (~50 min)."

    meta="$snap.meta"
    fmt=$(meta_get "$meta" format || echo inserts)

    read_counts; before=$TOTAL

    # -1 wraps the whole restore in ONE transaction: a failure halfway leaves
    # the catalog as it was rather than half-populated, which is the state
    # nobody would notice. replica mode skips the FK triggers the self-
    # referencing columns would otherwise trip on (see the TABLES note).
    if ! { printf 'set session_replication_role = replica;\n'; cat "$snap"; } \
        | docker exec -i "$CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -q -1; then
        hint=""
        # An adopted pre-GLO-223 snapshot is plain COPY, so it collides with the
        # rows seed.sql recreates. Measured, not guessed: it dies on
        # attribute_chips_pkey. Say what to do instead of leaving a raw psql error.
        [ "$fmt" != "copy" ] || hint="
That snapshot is the pre-GLO-223 COPY format, which cannot survive the rows
seed.sql recreates. If the catalog is still in the database, take a fresh one
with 'make catalog-snapshot'; if it is not, HANDOFF §9's seven scripts are the
rebuild."
        die "restore FAILED — the catalog is UNTOUCHED, because the whole load is one transaction.$hint"
    fi

    read_counts; after=$TOTAL
    [ "$after" -ge "$before" ] || die "restore ran but the catalog SHRANK ($before -> $after) — \
the snapshot at $snap is suspect. Older generations: $STORE"

    # Verify against what the snapshot said it held, per table. A restore that
    # half-succeeds has to be loud; the failure this catches is the one where
    # a table is quietly missing and everything still looks populated.
    want_total=$(meta_get "$meta" total || echo 0)
    if [ "${want_total:-0}" -gt 0 ] 2>/dev/null; then
        for c in "${COUNTS[@]}"; do
            t=${c%%=*}; got=${c#*=}
            want=$(meta_get "$meta" "table.$t" || echo 0)
            [ "$got" -ge "${want:-0}" ] || die "restore is INCOMPLETE: $t has $got rows, \
the snapshot recorded $want. The catalog is not what $snap says it is."
        done
    fi

    # replica mode meant no FK was checked on the way in, so check the ones
    # that matter on the way out rather than trusting the dump's row order.
    orphans=$(psql_q "select
        (select count(*) from public.products p left join public.brands b on b.id = p.brand_id where b.id is null)
      + (select count(*) from public.variants v left join public.products p on p.id = v.product_id where p.id is null)
      + (select count(*) from public.variant_images i left join public.variants v on v.id = i.variant_id where v.id is null)
      + (select count(*) from public.products p left join public.products f on f.id = p.forked_from where p.forked_from is not null and f.id is null)")
    [ "$orphans" = "0" ] || die "restore left $orphans orphaned catalog rows — \
the snapshot at $snap is internally inconsistent."

    printf 'catalog restored: %s -> %s rows from %s (verified against its manifest)\n' \
        "$before" "$after" "$snap"
    ;;
count)
    read_counts
    printf '%s\n' "$TOTAL"
    ;;
list)
    generations | while read -r s; do
        printf '%s\t%s rows\t%s\n' "$(basename "$s")" \
            "$(meta_get "$s.meta" total || echo '?')" "$(meta_get "$s.meta" created_at || echo '?')"
    done
    ;;
*)
    die "usage: $0 {save [--allow-shrink]|load|count|list}   (store: $STORE)"
    ;;
esac
