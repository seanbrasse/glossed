// GLO-79 · the source ladder's Shopify rung: studio images for DTC brands.
//
// Most indie beauty brands run Shopify, which exposes product data — including
// image URLs — at the public `/products.json` endpoint. These are the brand's
// own PDP hero shots (typically square, white or transparent background), the
// ideal input for background removal and two rungs above crowd photos on the
// ladder. Brands are curated by hand: each entry maps a storefront to the
// brand's `normalized_name` in our catalog, and only products we already carry
// get images — this rung images the catalog, it does not grow it.
//
// Matching is by brand + normalized title (the public payload carries no
// barcodes). Scoring, best first: title == our name + our shade · title == our
// name · shortest title containing our name. A wrong match here is visible on
// the shelf and cheap to fix (requeue with a better URL); the hand-check pass
// for the top products stays GLO-48's.
//
// Replacement semantics per GLO-79: a better-ranked source replaces a worse
// one — existing catalog images for a matched variant are deleted and the job
// requeued, so the pipeline writes the Shopify image in their place.
//
// Usage:
//   deno run --allow-net --allow-run --allow-env scripts/shopify_images.ts [--dry-run]

import { psqlArgs, targetLabel } from "./db.ts";

// Say the destination before writing to it.
console.log(`→ writing to ${targetLabel()}`);

const USER_AGENT = "Glossed-Dev/0.1 (seanbrasse@gmail.com)";
const dryRun = Deno.args.includes("--dry-run");

/// Storefront → the brand's normalized_name in our catalog.
const STORES: Record<string, string> = {
  "rhodeskin.com": "rhode",
  "www.rarebeauty.com": "rare beauty",
  "www.fentybeauty.com": "fenty beauty",
  "www.kosas.com": "kosas",
  "www.glossier.com": "glossier",
  "tower28beauty.com": "tower 28",
  "curlsmith.com": "curlsmith",
  "www.kravebeauty.com": "krave",
};

interface ShopifyProduct {
  title?: string;
  images?: { src?: string }[];
}

interface CatalogRow {
  variantID: string;
  name: string;
  shade: string;
}

// Mirrors normalize_name() closely enough for matching: lowercase, drop
// apostrophes, every other separator to one space. Used for comparison only —
// nothing normalized here is ever written.
function normalized(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

async function psql(statements: string): Promise<string> {
  const child = new Deno.Command("docker", {
    args: psqlArgs(["-q", "-t", "-A", "-F", "\t"]),
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(statements));
  await writer.close();
  const out = await child.output();
  const stderr = new TextDecoder().decode(out.stderr).trim();
  if (stderr) console.error(stderr.split("\n").slice(0, 10).join("\n"));
  return new TextDecoder().decode(out.stdout);
}

async function storefront(domain: string): Promise<ShopifyProduct[]> {
  const all: ShopifyProduct[] = [];
  for (let page = 1; page <= 8; page++) {
    const response = await fetch(`https://${domain}/products.json?limit=250&page=${page}`, {
      headers: { "user-agent": USER_AGENT },
    });
    if (!response.ok) {
      console.error(`  ${domain} page ${page}: HTTP ${response.status}`);
      break;
    }
    const body = await response.json();
    const products = (body.products ?? []) as ShopifyProduct[];
    all.push(...products);
    if (products.length < 250) break;
  }
  return all;
}

async function ourProducts(brand: string): Promise<CatalogRow[]> {
  const rows = await psql(`
select v.id, p.name, coalesce(v.shade_code, '')
  from products p
  join brands b on b.id = p.brand_id
  join variants v on v.product_id = p.id
 where b.normalized_name = normalize_name($b$${brand}$b$);`);
  return rows
    .split("\n")
    .filter((line) => line.includes("\t"))
    .map((line) => {
      const [variantID, name, shade] = line.split("\t");
      return { variantID, name, shade };
    });
}

/// Best Shopify product for one of ours, or null. See the header for scoring.
function match(row: CatalogRow, store: ShopifyProduct[]): string | null {
  const name = normalized(row.name);
  if (name.length < 4) return null;
  const withShade = row.shade ? `${name} ${normalized(row.shade)}` : null;
  const candidates = store
    .map((p) => ({ title: normalized(p.title ?? ""), src: p.images?.[0]?.src }))
    .filter((p) => p.src && p.title.includes(name));
  if (candidates.length === 0) return null;
  if (withShade) {
    const exact = candidates.find((p) => p.title === withShade);
    if (exact) return exact.src ?? null;
  }
  const plain = candidates.find((p) => p.title === name);
  if (plain) return plain.src ?? null;
  candidates.sort((a, b) => a.title.length - b.title.length);
  return candidates[0].src ?? null;
}

let matched = 0;
const statements: string[] = [];

for (const [domain, brand] of Object.entries(STORES)) {
  const [store, ours] = await Promise.all([storefront(domain), ourProducts(brand)]);
  let hits = 0;
  for (const row of ours) {
    const src = match(row, store);
    if (!src) continue;
    // The CDN serves any width; 1024 is plenty above the 512 derivative.
    const url = src.split("?")[0] + "?width=1024";
    statements.push(`
delete from variant_images where variant_id = '${row.variantID}' and kind = 'catalog';
delete from ingest_jobs where kind = 'image_fetch' and payload->>'variant_id' = '${row.variantID}';
insert into ingest_jobs (kind, payload)
values ('image_fetch', jsonb_build_object('variant_id', '${row.variantID}', 'url', $u$${url}$u$));`);
    hits++;
  }
  matched += hits;
  console.log(`${domain}: ${store.length} storefront products, ${ours.length} of ours, ${hits} matched`);
}

console.log(`\n${matched} variants matched to Shopify studio images`);
if (dryRun) {
  console.log("--dry-run: no writes");
  Deno.exit(0);
}
await runAll();

async function runAll() {
  await psql(statements.join("\n"));
  console.log(await psql(`
select state, count(*) from ingest_jobs where kind = 'image_fetch' group by state order by state;`));
}
