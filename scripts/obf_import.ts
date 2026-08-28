// GLO-78 · Fill the catalog from Open Beauty Facts.
//
// Data © Open Beauty Facts contributors, licensed under the Open Database
// License (ODbL) 1.0 — https://openbeautyfacts.org. Attribution is required
// wherever this data is shown ("Data © Open Beauty Facts contributors"), and
// share-alike applies to redistributed extracts of the database. A visible
// attribution line ships with the settings/about screen (GLO-21).
//
// What this does, per mapped category tag, most-scanned first:
//   OBF v2 search  →  brands / products / variants rows (source='obf')
//                  →  one ingest_jobs(kind='image_fetch') row per new variant,
//                     which is the queue scripts/catalog_images.ts consumes.
//
// All writes go through SQL so `normalize_name()` stays server-side — the
// client-side-normalization drift bug (see PersonalProductDraft's history)
// stays dead. Idempotent: an existing brand, product, or GTIN short-circuits
// its whole chain, so re-running never duplicates rows or jobs.
//
// Usage:
//   deno run --allow-net --allow-run scripts/obf_import.ts [--dry-run] [--max-pages N]
//
// Rate limits per OBF's published guidance: search ≤10 req/min, so pages are
// fetched 7s apart. A full run at the current taxonomy (~1.3k mappable
// records) takes a few minutes.

const USER_AGENT = "Glossed-Dev/0.1 (seanbrasse@gmail.com)";
const BASE = "https://world.openbeautyfacts.org/api/v2/search";
const PAGE_SIZE = 100;
const SEARCH_INTERVAL_MS = 7_000;
const CONTAINER = Deno.env.get("GLOSSED_DB_CONTAINER") ?? "supabase_db_glossed";

// Our category tree (seeded slugs) → OBF taxonomy tags, verified live against
// the facets on Aug 28 2026. Counts then: cleansers 303, facial-creams 454,
// perfumes 426, hair-gels 73, foundations 20, serums 2. Tags with nothing
// behind them (en:blushes) are left out rather than guessed at.
const CATEGORY_TAGS: Record<string, { domain: string; tags: string[] }> = {
  cleanser: { domain: "skincare", tags: ["en:cleansers"] },
  moisturizer: { domain: "skincare", tags: ["en:facial-creams"] },
  serum: { domain: "skincare", tags: ["en:serums"] },
  foundation: { domain: "makeup", tags: ["en:foundations"] },
  styler: { domain: "haircare", tags: ["en:hair-gels"] },
  fragrance: { domain: "fragrance", tags: ["en:perfumes"] },
};

interface ObfProduct {
  code?: string;
  product_name?: string;
  brands?: string;
  quantity?: string;
  image_front_url?: string;
  image_url?: string;
  ingredients_text?: string;
}

interface Candidate {
  slug: string;
  domain: string;
  gtin: string;
  name: string;
  brand: string;
  sizeML: number | null;
  imageURL: string;
  inci: string | null;
}

const dryRun = Deno.args.includes("--dry-run");
const maxPagesArg = Deno.args.indexOf("--max-pages");
const maxPages = maxPagesArg >= 0 ? Number(Deno.args[maxPagesArg + 1]) : 10;

// One printable line, capped. Anything that would break out of a dollar-quoted
// string is stripped rather than escaped — a product name has no business
// containing our quote tag.
function clean(raw: string, cap: number): string {
  return raw
    .replaceAll("$glossed$", "")
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, cap);
}

function quote(raw: string): string {
  return `$glossed$${raw}$glossed$`;
}

function candidate(slug: string, domain: string, p: ObfProduct): Candidate | null {
  const gtin = (p.code ?? "").trim();
  if (!/^\d{8,14}$/.test(gtin)) return null;
  const name = clean(p.product_name ?? "", 200);
  if (name.length < 2) return null;
  // OBF's brands field is comma-separated; the first entry is the brand.
  const brand = clean((p.brands ?? "").split(",")[0] ?? "", 80);
  if (brand.length < 2) return null;
  const imageURL = (p.image_front_url ?? p.image_url ?? "").trim();
  if (!imageURL.startsWith("https://")) return null;
  const sizeMatch = (p.quantity ?? "").match(/(\d+(?:\.\d+)?)\s*ml\b/i);
  const inciRaw = clean(p.ingredients_text ?? "", 5000);
  return {
    slug,
    domain,
    gtin,
    name,
    brand,
    sizeML: sizeMatch ? Number(sizeMatch[1]) : null,
    imageURL,
    inci: inciRaw.length > 2 ? inciRaw : null,
  };
}

/// The whole chain for one record. Each CTE gates the next, so an existing
/// product or GTIN means no variant and no job — idempotency by construction.
function sql(c: Candidate): string {
  const sizeML = c.sizeML === null ? "null" : String(c.sizeML);
  const inci = c.inci === null ? "null" : quote(c.inci);
  return `
insert into brands (name, normalized_name, source)
values (${quote(c.brand)}, normalize_name(${quote(c.brand)}), 'obf')
on conflict (normalized_name) do nothing;
with b as (
    select id from brands where normalized_name = normalize_name(${quote(c.brand)})
), c as (
    select id, domain from categories where slug = '${c.slug}'
), p as (
    insert into products (brand_id, category_id, domain, name, normalized_name, scope, source, inci_raw)
    select b.id, c.id, c.domain, ${quote(c.name)}, normalize_name(${quote(c.name)}), 'canonical', 'obf', ${inci}
    from b, c
    where not exists (
        select 1 from products dup
        where dup.brand_id = b.id and dup.normalized_name = normalize_name(${quote(c.name)})
    )
    returning id
), v as (
    insert into variants (product_id, kind, gtin, size_ml, source)
    select p.id, 'default', '${c.gtin}', ${sizeML}, 'obf' from p
    on conflict do nothing
    returning id
)
insert into ingest_jobs (kind, payload)
select 'image_fetch', jsonb_build_object('variant_id', v.id, 'url', ${quote(c.imageURL)})
from v;`;
}

async function fetchPage(tag: string, page: number): Promise<ObfProduct[]> {
  const url = `${BASE}?categories_tags=${tag}` +
    `&fields=code,product_name,brands,quantity,image_front_url,image_url,ingredients_text` +
    `&page_size=${PAGE_SIZE}&page=${page}&sort_by=unique_scans_n`;
  const response = await fetch(url, { headers: { "user-agent": USER_AGENT } });
  if (!response.ok) {
    console.error(`  ${tag} page ${page}: HTTP ${response.status} — stopping this tag`);
    return [];
  }
  const body = await response.json();
  return (body.products ?? []) as ObfProduct[];
}

async function runSQL(statements: string): Promise<string> {
  const psql = new Deno.Command("docker", {
    args: ["exec", "-i", CONTAINER, "psql", "-U", "postgres", "-d", "postgres", "-q"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = psql.stdin.getWriter();
  await writer.write(new TextEncoder().encode(statements));
  await writer.close();
  const out = await psql.output();
  const stderr = new TextDecoder().decode(out.stderr).trim();
  if (stderr) console.error(stderr.split("\n").slice(0, 20).join("\n"));
  return new TextDecoder().decode(out.stdout);
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

let fetched = 0;
let usable = 0;
const chunks: string[] = [];

for (const [slug, { domain, tags }] of Object.entries(CATEGORY_TAGS)) {
  for (const tag of tags) {
    for (let page = 1; page <= maxPages; page++) {
      const products = await fetchPage(tag, page);
      fetched += products.length;
      let pageUsable = 0;
      for (const p of products) {
        const c = candidate(slug, domain, p);
        if (c) {
          chunks.push(sql(c));
          pageUsable++;
        }
      }
      usable += pageUsable;
      console.log(`${tag} page ${page}: ${products.length} fetched, ${pageUsable} usable`);
      if (products.length < PAGE_SIZE) break;
      await sleep(SEARCH_INTERVAL_MS);
    }
    await sleep(SEARCH_INTERVAL_MS);
  }
}

console.log(`\n${fetched} records fetched, ${usable} pass the filters (brand + name + barcode + image)`);

if (dryRun) {
  console.log("--dry-run: no writes");
  Deno.exit(0);
}

await runSQL(chunks.join("\n"));

const summary = await runSQL(`
select 'brands' as t, count(*) from brands where source = 'obf'
union all select 'products', count(*) from products where source = 'obf'
union all select 'variants', count(*) from variants where source = 'obf'
union all select 'image jobs', count(*) from ingest_jobs where kind = 'image_fetch' and state = 'queued';
`);
console.log(summary);
