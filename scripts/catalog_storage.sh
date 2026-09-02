#!/usr/bin/env bash
# GLO-223, the half the snapshot missed — the catalog IMAGES must survive a
# `supabase db reset` too.
#
# What happened (Sept 1): every product photo in the app went back to the drawn
# placeholder. The rows were fine — 3,206 products, 7,625 `variant_images`, all
# restored by catalog_snapshot.sh — and 1.9 GB of cutouts were still sitting on
# the storage volume. What a reset drops is the `storage` SCHEMA: the bucket
# row and the 13,877 object rows Supabase Storage answers from. The files
# outlive the reset; the index to them does not. Storage then says "Bucket not
# found" for files it is literally standing on, and `ProductImage` renders its
# honest floor. Nothing errors. Photos died Aug 31 ~11:39 UTC — the timestamp of
# the reset that session — and nobody noticed for a day.
#
# The bucket itself is now declared in supabase/config.toml, so `supabase start`
# and `db reset` recreate it (the CLI seeds declared buckets on both). This
# script restores the OBJECT rows: it inventories the volume inside the storage
# container — bucket/<variant_id>/cut512.png/<version> is the file backend's
# layout, and a public GET needs a storage.objects row whose `version` matches
# that directory — and registers whatever is missing. Idempotent; safe to run
# whenever the counts below disagree.
#
# Two other durability notes stated once, here:
#  - The files live in the storage container's volume, not on this machine.
#    `supabase stop --no-backup` or `docker volume rm` loses them, and the only
#    rebuild is scripts/catalog_images.ts (~50 min, Vision cutouts on a Mac).
#  - Hosted has NO catalog images (0 buckets, 0 objects, 0 products as of
#    Sept 1). This script is local-only; promoting the catalog is its own job.
set -euo pipefail

DB="${GLOSSED_DB_CONTAINER:-supabase_db_glossed}"
STORAGE="${GLOSSED_STORAGE_CONTAINER:-supabase_storage_glossed}"
BUCKET="${GLOSSED_CATALOG_BUCKET:-catalog}"
API="${GLOSSED_SUPABASE_URL:-http://127.0.0.1:54321}"

die() { printf '%s\n' "$*" >&2; exit 1; }
psql_q() { docker exec -i "$DB" psql -U postgres -tA -v ON_ERROR_STOP=1 "$@"; }

docker exec "$DB" true 2>/dev/null || die "no database container '$DB' — is \`supabase start\` running?"
docker exec "$STORAGE" true 2>/dev/null || die "no storage container '$STORAGE' — is \`supabase start\` running?"

# storage-api v1.70's file backend nests the tenant twice on local
# (/mnt/stub/stub/<bucket>); probe rather than trust the arithmetic.
volume_root() {
    docker exec "$STORAGE" sh -c '
        base="${FILE_STORAGE_BACKEND_PATH:-/mnt}/${TENANT_ID:-stub}"
        for d in "$base/${TENANT_ID:-stub}" "$base"; do
            [ -d "$d/'"$BUCKET"'" ] && { echo "$d"; exit 0; }
        done
        echo "$base"'
}

ensure_bucket() {
    if [ "$(psql_q -c "select count(*) from storage.buckets where id = '$BUCKET'")" = "1" ]; then
        return
    fi
    # Through the API rather than an insert, so storage's own defaults apply.
    local key
    key=$(supabase status -o json 2>/dev/null | sed -n 's/.*"SERVICE_ROLE_KEY":"\([^"]*\)".*/\1/p')
    [ -n "$key" ] || die "could not read SERVICE_ROLE_KEY from \`supabase status\`"
    curl -sf -X POST "$API/storage/v1/bucket" \
        -H "Authorization: Bearer $key" -H "apikey: $key" -H "Content-Type: application/json" \
        -d "{\"id\":\"$BUCKET\",\"name\":\"$BUCKET\",\"public\":true}" > /dev/null \
        || die "could not create bucket '$BUCKET' (is storage up? does supabase/config.toml declare it?)"
    printf 'created public bucket %s\n' "$BUCKET"
}

# name<TAB>version<TAB>size, newest version per object name — a re-upload
# leaves two version files behind and only one is the row.
inventory() {
    local root; root=$(volume_root)
    docker exec "$STORAGE" sh -c "cd '$root/$BUCKET' 2>/dev/null && find . -type f -exec stat -c '%n %s %Y' {} +" \
        | awk '{
            sub(/^\.\//, "", $1); n = split($1, p, "/");
            name = p[1]; for (i = 2; i < n; i++) name = name "/" p[i];
            if (!(name in seen) || $3 > seen[name]) { seen[name] = $3; ver[name] = p[n]; size[name] = $2 }
        } END { for (k in seen) print k "\t" ver[k] "\t" size[k] }'
}

case "${1:-reconcile}" in
count)
    printf 'bucket rows: %s\nobject rows: %s\nfiles on volume: %s\nvariant_images without a file: %s\n' \
        "$(psql_q -c "select count(*) from storage.buckets where id = '$BUCKET'")" \
        "$(psql_q -c "select count(*) from storage.objects where bucket_id = '$BUCKET'")" \
        "$(inventory | wc -l | tr -d ' ')" \
        "$(psql_q -c "select count(*) from public.variant_images vi left join storage.objects o
                      on o.bucket_id = '$BUCKET' and o.name = vi.r2_key where o.id is null")"
    ;;
reconcile)
    ensure_bucket
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    inventory > "$tmp"
    files=$(wc -l < "$tmp" | tr -d ' ')
    [ "$files" -gt 0 ] || die "the storage volume holds no files for bucket '$BUCKET' — nothing to register. \
The rebuild is scripts/catalog_images.ts (~50 min)."
    docker cp "$tmp" "$DB:/tmp/catalog_storage_inventory.tsv"
    before=$(psql_q -c "select count(*) from storage.objects where bucket_id = '$BUCKET'")
    psql_q -q <<SQL
create temp table inv (name text, version text, size bigint);
\\copy inv from '/tmp/catalog_storage_inventory.tsv' with (format text)
insert into storage.objects (bucket_id, name, owner, version, metadata)
select '$BUCKET', name, null, version,
       jsonb_build_object('eTag', '', 'size', size, 'mimetype', 'image/png',
                          'cacheControl', 'max-age=3600', 'lastModified', now(),
                          'contentLength', size, 'httpStatusCode', 200)
from inv
on conflict (bucket_id, name) do update set version = excluded.version, metadata = excluded.metadata;
SQL
    after=$(psql_q -c "select count(*) from storage.objects where bucket_id = '$BUCKET'")
    missing=$(psql_q -c "select count(*) from public.variant_images vi left join storage.objects o
                         on o.bucket_id = '$BUCKET' and o.name = vi.r2_key where o.id is null")
    printf 'catalog images: %s object rows -> %s, from %s files on the volume; %s variant_images still without a file\n' \
        "$before" "$after" "$files" "$missing"
    # Prove one serves, because "rows exist" is exactly the claim that was
    # true while every photo was missing.
    key=$(psql_q -c "select name from storage.objects where bucket_id = '$BUCKET' limit 1")
    code=$(curl -s -o /dev/null -w '%{http_code}' "$API/storage/v1/object/public/$BUCKET/$key")
    [ "$code" = "200" ] || die "registered, but GET /object/public/$BUCKET/$key returned $code — storage is not serving the volume"
    ;;
*)
    die "usage: $0 {reconcile|count}"
    ;;
esac
