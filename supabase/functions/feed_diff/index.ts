// feed_diff — the transport half. Claims one queued ingest_jobs row, reads the
// feed (the committed fixture until the publisher accounts exist), plans every
// row (diff.ts), applies the plans, and finishes or dead-letters the job.
//
// Service-role on purpose: ingest writes canonical catalog rows, which no user
// policy allows — that is the point of the scope column. The caller still has
// to hold the function secret: verify_jwt lets any signed-in user through, and
// "any user can run ingest" would be a denial-of-catalog waiting to happen.
//
// Dry-run mode (`{"dry_run": true}`) plans everything and writes nothing —
// the acceptance criterion that makes a feed inspectable before it lands.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { resolveSecretKey } from "../_shared/credentials.ts";
import {
  afterFailure,
  backoffSeconds,
  type FeedRow,
  gtin14,
  type KnownProduct,
  type KnownVariant,
  normalizeName,
  type Plan,
  plan,
} from "./diff.ts";

const json = (body: unknown, status: number): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

async function loadFeed(): Promise<FeedRow[]> {
  const url = new URL("./fixture_feed.json", import.meta.url);
  const text = await Deno.readTextFile(url);
  return (JSON.parse(text) as { rows: FeedRow[] }).rows;
}

/** Plans the whole feed against current catalog state. Reads only. */
export async function planFeed(db: SupabaseClient, rows: FeedRow[]): Promise<Plan[]> {
  const codes = rows.map((r) => gtin14(r.gtin)).filter((c): c is string => c !== null);
  const variantsByGTIN = new Map<string, KnownVariant>();
  if (codes.length > 0) {
    // gtin is stored as scanned; match on the padded form of what is stored.
    const { data, error } = await db
      .from("variants")
      .select("id, product_id, gtin")
      .not("gtin", "is", null);
    if (error) throw error;
    for (const v of data ?? []) {
      const code = gtin14(v.gtin);
      if (code && codes.includes(code)) {
        variantsByGTIN.set(code, { variant_id: v.id, product_id: v.product_id, gtin: v.gtin });
      }
    }
  }

  const brandNames = [...new Set(rows.map((r) => normalizeName(r.brand)).filter(Boolean))];
  const { data: brands, error: brandError } = await db
    .from("brands")
    .select("id, normalized_name")
    .in("normalized_name", brandNames);
  if (brandError) throw brandError;
  const brandID = new Map((brands ?? []).map((b) => [b.normalized_name, b.id]));

  const blocks = new Map<string, KnownProduct[]>();
  for (const name of brandNames) {
    const id = brandID.get(name);
    if (!id) {
      blocks.set(name, []);
      continue;
    }
    const { data: products, error: productError } = await db
      .from("products")
      .select("id, brand_id, normalized_name")
      .eq("brand_id", id)
      .eq("scope", "canonical")
      .is("merged_into", null);
    if (productError) throw productError;
    blocks.set(
      name,
      (products ?? []).map((p) => ({
        product_id: p.id,
        brand_id: p.brand_id,
        normalized_name: p.normalized_name,
      })),
    );
  }

  return rows.map((row) => plan(row, variantsByGTIN, blocks.get(normalizeName(row.brand)) ?? []));
}

/** Applies one plan. Every branch is one write path:
 *
 * - `queue_candidate` goes to the merge queue as a feed-row pair (0012) —
 *   never a product write; the adjudicator resolves it with §16's three verbs.
 * - `insert_product` creates the canonical product + default variant: the
 *   block-and-match already said nothing similar exists in the brand, which
 *   is tech/01 §4's "low confidence creates".
 */
async function apply(db: SupabaseClient, decision: Plan): Promise<void> {
  switch (decision.kind) {
    case "update_variant": {
      const { error } = await db
        .from("variants")
        .update({
          price_cents: decision.row.price_cents,
          availability: decision.row.availability,
          source: "feed",
          last_verified: new Date().toISOString(),
        })
        .eq("id", decision.variantID);
      if (error) throw error;
      return;
    }
    case "delist_variant": {
      // Delisting is availability, not deletion — the shelf can still say
      // "discontinued" about a thing you own.
      const { error } = await db
        .from("variants")
        .update({ availability: "delisted", source: "feed" })
        .eq("id", decision.variantID);
      if (error) throw error;
      return;
    }
    case "queue_candidate": {
      const { error } = await db.from("merge_candidates").insert({
        product_a: decision.productID,
        feed_row: decision.row,
        similarity: decision.similarity,
        state: "pending",
      });
      if (error) throw error;
      return;
    }
    case "insert_product": {
      const row = decision.row;
      const { data: brand, error: brandError } = await db
        .from("brands")
        .select("id")
        .eq("normalized_name", normalizeName(row.brand))
        .maybeSingle();
      if (brandError) throw brandError;
      const { data: category, error: categoryError } = await db
        .from("categories")
        .select("id")
        .eq("slug", row.category_slug)
        .maybeSingle();
      if (categoryError) throw categoryError;
      // A brand or category the catalog has never seen is a curation
      // question, not an insert — it queues as an unmatched pair against
      // nothing... which the queue cannot hold, so it is skipped loudly in
      // the response counts instead. Brand creation is deliberate work.
      if (!brand || !category) {
        throw new Error(`unknown ${brand ? "category" : "brand"} for "${row.name}"`);
      }

      const { data: product, error: productError } = await db
        .from("products")
        .insert({
          brand_id: brand.id,
          category_id: category.id,
          domain: row.domain,
          name: row.name,
          normalized_name: normalizeName(row.name),
          scope: "canonical",
          source: "feed",
          last_verified: new Date().toISOString(),
        })
        .select("id")
        .single();
      if (productError) throw productError;

      const { error: variantError } = await db.from("variants").insert({
        product_id: product.id,
        kind: row.shade_code ? "shade" : "default",
        shade_code: row.shade_code ?? null,
        size_ml: row.size_ml ?? null,
        gtin: row.gtin ?? null,
        price_cents: row.price_cents ?? null,
        availability: row.availability ?? null,
        source: "feed",
        last_verified: new Date().toISOString(),
      });
      if (variantError) throw variantError;
      return;
    }
    case "skip":
      return;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const secret = Deno.env.get("INGEST_SECRET");
  if (!secret || req.headers.get("x-ingest-secret") !== secret) {
    return json({ error: "unauthenticated" }, 401);
  }

  let body: { dry_run?: boolean };
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", resolveSecretKey(Deno.env.get));

  // Claim exactly one runnable job. The state filter in the update is the
  // lock: two concurrent invocations race, one wins, the other claims nothing.
  const { data: jobs, error: claimError } = await db
    .from("ingest_jobs")
    .update({ state: "running", updated_at: new Date().toISOString() })
    .eq("state", "queued")
    .eq("kind", "feed_diff")
    .lte("run_after", new Date().toISOString())
    .select("id, attempts")
    .limit(1);
  if (claimError) return json({ error: "claim failed" }, 500);
  const job = jobs?.[0];
  if (!job) return json({ claimed: false }, 200);

  try {
    const rows = await loadFeed();
    const plans = await planFeed(db, rows);
    const failures: { index: number; reason: string }[] = [];
    if (!body.dry_run) {
      for (const [index, decision] of plans.entries()) {
        try {
          await apply(db, decision);
        } catch (error) {
          // One bad row costs itself, not the feed. It stays in the response
          // so the run is inspectable, and the job still completes.
          failures.push({ index, reason: String(error).slice(0, 200) });
        }
      }
    }

    await db.from("ingest_jobs")
      .update({ state: "done", updated_at: new Date().toISOString() })
      .eq("id", job.id);

    const counts: Record<string, number> = {};
    for (const p of plans) counts[p.kind] = (counts[p.kind] ?? 0) + 1;
    return json(
      { claimed: true, dry_run: body.dry_run ?? false, job: job.id, counts, failures },
      200,
    );
  } catch (error) {
    console.error("feed_diff failed", error);
    const attempts = job.attempts + 1;
    await db.from("ingest_jobs")
      .update({
        state: afterFailure(attempts),
        attempts,
        last_error: String(error).slice(0, 500),
        run_after: new Date(Date.now() + backoffSeconds(attempts) * 1000).toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", job.id);
    return json({ error: "feed_diff failed", job: job.id }, 500);
  }
});
