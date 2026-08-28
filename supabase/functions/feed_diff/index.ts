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

/** Applies one plan.
 *
 * Two kinds deliberately write nothing yet. `queue_candidate` is PR 2's: the
 * adjudicator defines what a merge_candidates row means, and inserting a
 * placeholder pair today would be a claim the schema cannot cash. And
 * `insert_product` waits with it — a new canonical row should only exist after
 * the dedupe pass has said it is genuinely new. Both are counted in the
 * response so a dry run shows exactly what the full pipeline will do. */
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
      // Delisting is product-level state reached through the variant's product;
      // the variant itself keeps availability so the shelf can say "discontinued".
      const { error } = await db
        .from("variants")
        .update({ availability: "delisted", source: "feed" })
        .eq("id", decision.variantID);
      if (error) throw error;
      return;
    }
    case "queue_candidate":
    case "insert_product":
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
    if (!body.dry_run) {
      for (const decision of plans) await apply(db, decision);
    }

    await db.from("ingest_jobs")
      .update({ state: "done", updated_at: new Date().toISOString() })
      .eq("id", job.id);

    const counts: Record<string, number> = {};
    for (const p of plans) counts[p.kind] = (counts[p.kind] ?? 0) + 1;
    return json({ claimed: true, dry_run: body.dry_run ?? false, job: job.id, counts }, 200);
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
