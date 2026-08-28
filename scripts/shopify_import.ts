// GLO-81 · Shopify catalog fill — the source ladder's rung 3 grows the spine.
//
// Sean's call (Aug 28, session 6, after reviewing OBF's rhode coverage): OBF
// is too thin as a catalog source for current brands. Most indie DTC beauty
// runs Shopify, and the public `/products.json` endpoint carries titles,
// variants (shades/sizes), prices, barcodes where the store sets them, and
// the brand's own hero images — a catalog source and an image source in one
// fetch. This supersedes `shopify_images.ts`'s "this rung images the catalog,
// it does not grow it": that script images what exists; this one adds what
// doesn't.
//
// Conservative on purpose. A storefront sells sweaters, candles and gift
// cards next to the serum, so only explicitly mapped `product_type`s pass,
// sets/kits/bundles are excluded by title, and zero-priced rows (gifts with
// purchase) drop. Unmapped types are counted and printed — that list is the
// next mapping decision, not silent loss.
//
// Same write path as obf_import.ts: server-side normalize_name(), an
// idempotent CTE chain (existing brand/product/GTIN short-circuits — re-runs
// never duplicate), one ingest_jobs(kind='image_fetch') per new variant. The
// variant's own featured image wins over the product's first image, because
// a shade's card should show that shade.
//
// Usage:
//   deno run --allow-net --allow-run --allow-env scripts/shopify_import.ts [--dry-run] [--store host]

const USER_AGENT = "Glossed-Dev/0.1 (seanbrasse@gmail.com)";
const CONTAINER = Deno.env.get("GLOSSED_DB_CONTAINER") ?? "supabase_db_glossed";
const PAGE_SIZE = 250;
const FETCH_INTERVAL_MS = 1_000;

const dryRun = Deno.args.includes("--dry-run");
const storeArg = Deno.args.indexOf("--store");
const onlyStore = storeArg >= 0 ? Deno.args[storeArg + 1] : null;

/// Storefront → the brand's name in our catalog. Every host verified to
/// answer /products.json before being listed (curl 200, Aug 28 2026).
const STORES: Record<string, string> = {
  "rhodeskin.com": "rhode",
  "www.rarebeauty.com": "rare beauty",
  "www.fentybeauty.com": "fenty beauty",
  "www.kosas.com": "kosas",
  "www.glossier.com": "glossier",
  "tower28beauty.com": "tower 28",
  "curlsmith.com": "curlsmith",
  "www.kravebeauty.com": "krave",
  "www.theouai.com": "ouai",
  "iliabeauty.com": "ilia",
  "www.glowrecipe.com": "glow recipe",
  "www.summerfridays.com": "summer fridays",
};

/// product_type (lowercased) → our category slug. Only what we can place —
/// a "Dog Toy" has no bay. `lip` is the one category this ticket adds to the
/// seeded slice (flagged for workshop on GLO-81): rhode's flagship line is
/// lip, and a fill that cannot carry the products Sean asked for is not a
/// fill. Keyed on exact type; the regex fallback below catches phrasing
/// variants ("Liquid Blush", "Gel Cleanser").
const TYPE_RULES: [RegExp, string][] = [
  [/\blip\b|lipstick|lip\s?(gloss|oil|balm|liner|butter|cream|tint|treatment|makeup)/i, "lip"],
  [/\bblush\b|lip & cheek|\bcheek\b/i, "blush"],
  [/foundation|skin tint/i, "foundation"],
  [/cleanser|face wash|facial wash|makeup remover/i, "cleanser"],
  [/moisturi[sz]er|face cream|facial cream|barrier cream|night cream/i, "moisturizer"],
  [/\bserum\b/i, "serum"],
  [/hair gel|styler|pomade|hair paste|mousse|texture spray|hair balm|styling/i, "styler"],
  [/fragrance|eau de|perfume|cologne|parfum/i, "fragrance"],
];

/// Things that are not one product: bundles, and store furniture that
/// sometimes wears a mappable type ("Lip Set").
const EXCLUDED = /\b(set|sets|kit|duo|trio|bundle|collection|gift card|sample|merch)\b/i;

interface ShopifyVariant {
  title?: string;
  price?: string;
  barcode?: string | null;
  option1?: string | null;
  option2?: string | null;
  option3?: string | null;
  featured_image?: { src?: string } | null;
}

interface ShopifyProduct {
  title?: string;
  product_type?: string;
  variants?: ShopifyVariant[];
  images?: { src?: string }[];
  options?: { name?: string; position?: number }[];
}

interface VariantRow {
  shade: string | null;
  sizeML: number | null;
  gtin: string | null;
  priceCents: number | null;
  imageURL: string | null;
}

interface Candidate {
  slug: string;
  brand: string;
  name: string;
  variants: VariantRow[];
}

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

function categoryFor(p: ShopifyProduct): string | null {
  const signal = `${p.product_type ?? ""} ${p.title ?? ""}`;
  if (EXCLUDED.test(signal)) return null;
  for (const [pattern, slug] of TYPE_RULES) {
    if (pattern.test(p.product_type ?? "")) return slug;
  }
  // A mixed type needs the title to split it: fenty files 70 products under
  // "blushes & bronzers", and only the blushes have a bay. Title-only, and
  // only for this known mixed bucket — a generic title fallback is how a
  // "blush pink lip liner" lands in the wrong category.
  if (/blushes & bronzers/i.test(p.product_type ?? "") && /blush/i.test(p.title ?? "")) {
    return "blush";
  }
  return null;
}

function sizeFrom(...texts: (string | undefined | null)[]): number | null {
  for (const text of texts) {
    const match = (text ?? "").match(/(\d+(?:\.\d+)?)\s*ml\b/i);
    if (match) return Number(match[1]);
  }
  return null;
}

function candidate(brand: string, p: ShopifyProduct): Candidate | null {
  const slug = categoryFor(p);
  if (!slug) return null;
  const name = clean((p.title ?? "").toLowerCase(), 200);
  if (name.length < 2) return null;
  // GLO-84's guard, mirrored: store-authored titles make this unlikely, but
  // a digits-only title names nothing wherever it came from.
  if (/^[\d\s.,-]+$/.test(name)) return null;
  // Which option position carries the shade, per this product's own schema.
  const shadePosition = (p.options ?? [])
    .find((o) => /^(shade|colou?r)$/i.test(o.name ?? ""))?.position;
  const sizePosition = (p.options ?? [])
    .find((o) => /^size$/i.test(o.name ?? ""))?.position;
  const fallbackImage = (p.images ?? [])[0]?.src ?? null;
  const variants: VariantRow[] = [];
  for (const v of p.variants ?? []) {
    const price = Number(v.price ?? "0");
    if (!(price > 0)) continue; // gifts-with-purchase and placeholders
    const options = [v.option1, v.option2, v.option3];
    const shadeRaw = shadePosition ? options[shadePosition - 1] ?? "" : "";
    const shade = clean(shadeRaw.toLowerCase(), 80);
    const sizeText = sizePosition ? options[sizePosition - 1] : null;
    const barcode = (v.barcode ?? "").trim();
    const image = (v.featured_image?.src ?? fallbackImage ?? "").trim();
    variants.push({
      shade: shade.length > 0 ? shade : null,
      sizeML: sizeFrom(sizeText, v.title, p.title),
      gtin: /^\d{8,14}$/.test(barcode) ? barcode : null,
      priceCents: Number.isFinite(price) ? Math.round(price * 100) : null,
      imageURL: image.startsWith("https://cdn.shopify.com/") ? image : null,
    });
  }
  if (variants.length === 0) return null;
  return { slug, brand, name, variants };
}

/// One product's whole chain. The product gate short-circuits everything —
/// a product OBF already brought in keeps its rows, and this fill only adds
/// what is missing. Variants insert per-row so one bad barcode cannot sink
/// its siblings; `on conflict do nothing` covers GTIN collisions.
function sql(c: Candidate): string {
  const parts: string[] = [`
insert into brands (name, normalized_name, source)
values (${quote(c.brand)}, normalize_name(${quote(c.brand)}), 'shopify')
on conflict (normalized_name) do nothing;
with b as (
    select id from brands where normalized_name = normalize_name(${quote(c.brand)})
), c as (
    select id, domain from categories where slug = '${c.slug}'
)
insert into products (brand_id, category_id, domain, name, normalized_name, scope, source)
select b.id, c.id, c.domain, ${quote(c.name)}, normalize_name(${quote(c.name)}), 'canonical', 'shopify'
from b, c
where not exists (
    select 1 from products dup
    where dup.brand_id = b.id and dup.normalized_name = normalize_name(${quote(c.name)})
);`];
  for (const v of c.variants) {
    const gtin = v.gtin === null ? "null" : `'${v.gtin}'`;
    const shade = v.shade === null ? "null" : quote(v.shade);
    const sizeML = v.sizeML === null ? "null" : String(v.sizeML);
    const price = v.priceCents === null ? "null" : String(v.priceCents);
    parts.push(`
with p as (
    select p.id from products p
    join brands b on b.id = p.brand_id
    where b.normalized_name = normalize_name(${quote(c.brand)})
      and p.normalized_name = normalize_name(${quote(c.name)})
      and p.source = 'shopify'
), v as (
    insert into variants (product_id, kind, shade_code, size_ml, gtin, price_cents, source)
    select p.id, 'default', ${shade}, ${sizeML}, ${gtin}, ${price}, 'shopify' from p
    where not exists (
        select 1 from variants dup
        where dup.product_id = p.id
          and dup.shade_code is not distinct from ${shade}
          and dup.size_ml is not distinct from ${sizeML}
    )
    on conflict do nothing
    returning id
)
insert into ingest_jobs (kind, payload)
select 'image_fetch', jsonb_build_object('variant_id', v.id, 'url', ${quote(v.imageURL ?? "")})
from v
where ${v.imageURL === null ? "false" : "true"};`);
  }
  return parts.join("\n");
}

async function fetchPage(host: string, page: number): Promise<ShopifyProduct[]> {
  const url = `https://${host}/products.json?limit=${PAGE_SIZE}&page=${page}`;
  const response = await fetch(url, { headers: { "user-agent": USER_AGENT } });
  if (!response.ok) {
    console.error(`  ${host} page ${page}: HTTP ${response.status} — stopping this store`);
    return [];
  }
  const body = await response.json();
  return (body.products ?? []) as ShopifyProduct[];
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

/// The shade token some stores put in the title: "bright fix eye brightener
/// — almond butter". Em-dash with spaces, store-authored and consistent.
const SHADE_SUFFIX = /^(.{2,}?) — (.+)$/;

/// GLO-85's collapse: a store that models every shade as its own product
/// (fenty: 562 rows) becomes one product per franchise with shade variants —
/// the shape rare beauty already arrives in, and the shape the variant-pick
/// sheet exists for. Only groups of two or more collapse: a lone em-dash
/// title keeps its full name, because there the suffix may be identity
/// ("peptide lip tint honey mango" is one product), and collapsing on a
/// single sighting is how the wrong-franchise class of bug starts.
function collapseShades(candidates: Candidate[]): Candidate[] {
  const byBase = new Map<string, Candidate[]>();
  const out: Candidate[] = [];
  for (const c of candidates) {
    const match = c.name.match(SHADE_SUFFIX);
    if (match) {
      const key = `${c.slug}|${match[1].trim()}`;
      byBase.set(key, [...byBase.get(key) ?? [], c]);
    } else {
      out.push(c);
    }
  }
  for (const [key, group] of byBase) {
    if (group.length === 1) {
      out.push(group[0]);
      continue;
    }
    const base = key.split("|")[1];
    const variants = group.flatMap((member) => {
      const shade = (member.name.match(SHADE_SUFFIX)?.[2] ?? "")
        .replace(/^#/, "").trim();
      // The title's shade names the variant unless the store's own option
      // schema already did — the option is the stronger claim.
      return member.variants.map((v) => ({ ...v, shade: v.shade ?? (shade || null) }));
    });
    out.push({ slug: group[0].slug, brand: group[0].brand, name: base, variants });
  }
  return out;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

let fetched = 0;
let usable = 0;
const unmappedTypes = new Map<string, number>();
const chunks: string[] = [];

for (const [host, brand] of Object.entries(STORES)) {
  if (onlyStore && host !== onlyStore) continue;
  const storeCandidates: Candidate[] = [];
  for (let page = 1; page <= 8; page++) {
    const products = await fetchPage(host, page);
    fetched += products.length;
    for (const p of products) {
      const c = candidate(brand, p);
      if (c) {
        storeCandidates.push(c);
      } else if (!EXCLUDED.test(`${p.product_type ?? ""} ${p.title ?? ""}`)) {
        const key = (p.product_type ?? "(none)").toLowerCase();
        unmappedTypes.set(key, (unmappedTypes.get(key) ?? 0) + 1);
      }
    }
    if (products.length < PAGE_SIZE) break;
    await sleep(FETCH_INTERVAL_MS);
  }
  const collapsed = collapseShades(storeCandidates);
  for (const c of collapsed) {
    chunks.push(sql(c));
  }
  usable += collapsed.length;
  console.log(
    `${host}: ${collapsed.length} products` +
      (collapsed.length < storeCandidates.length
        ? ` (${storeCandidates.length} rows — per-shade titles collapsed)`
        : ""),
  );
  await sleep(FETCH_INTERVAL_MS);
}

console.log(`\n${fetched} records fetched, ${usable} mapped to a category`);
const skipped = [...unmappedTypes.entries()].sort((a, b) => b[1] - a[1]).slice(0, 25);
console.log("unmapped types (the next mapping decision, not silent loss):");
for (const [type, count] of skipped) console.log(`  ${countstr(count)} ${type}`);
function countstr(count: number): string {
  return String(count).padStart(4);
}

if (dryRun) {
  console.log("--dry-run: no writes");
  Deno.exit(0);
}

await runSQL(chunks.join("\n"));

const summary = await runSQL(`
select 'brands' as t, count(*) from brands where source = 'shopify'
union all select 'products', count(*) from products where source = 'shopify'
union all select 'variants', count(*) from variants where source = 'shopify'
union all select 'queued image jobs', count(*) from ingest_jobs where kind = 'image_fetch' and state = 'queued';
`);
console.log(summary);
