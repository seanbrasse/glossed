// inci_enrich — the transport half. Once per product, cached forever; a
// refresh only compares (PRD §15). Source: Open Beauty Facts, looked up by
// the variant's GTIN — the only key both sides hold exactly.
//
// Docs (read Aug 2026): the OFF-family API serves
//   GET https://world.openbeautyfacts.org/api/v2/product/{barcode}.json
// with `fields` selection; a custom User-Agent of the form
// "AppName/Version (contact)" is mandatory, and reads are limited to
// ~15 req/min/IP — which is why one run touches at most 12 products.
// The paid INCI API named in tech/01 §4 needs an account nobody has yet;
// until then OBF is the one source, and a product it cannot describe stays
// undescribed — empty beats fabricated.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { resolveSecretKey } from "../_shared/credentials.ts";
import { plan } from "./enrich.ts";

const USER_AGENT = "GlossedIngest/0.1 (ingest@glossed.app)";
export const MAX_PRODUCTS_PER_RUN = 12;

const json = (body: unknown, status: number): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

async function fetchINCI(gtin: string): Promise<string | null> {
  const url = `https://world.openbeautyfacts.org/api/v2/product/${
    encodeURIComponent(gtin)
  }.json?fields=ingredients_text`;
  const response = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
  if (!response.ok) return null;
  const body = await response.json() as { product?: { ingredients_text?: string } };
  return body.product?.ingredients_text ?? null;
}

async function attachChips(db: SupabaseClient, productID: string, slugs: string[]): Promise<void> {
  if (slugs.length === 0) return;
  // Insert by slug lookup: a derivation whose slug is not in the vocabulary
  // inserts nothing — new chips are a vocabulary PR, not an ingest side effect.
  const { data: chips, error } = await db
    .from("attribute_chips")
    .select("id, slug")
    .in("slug", slugs);
  if (error) throw error;
  for (const chip of chips ?? []) {
    const { error: linkError } = await db
      .from("product_attributes")
      .upsert(
        { product_id: productID, attribute_chip_id: chip.id, source: "inci" },
        { onConflict: "product_id,attribute_chip_id", ignoreDuplicates: true },
      );
    if (linkError) throw linkError;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const secret = Deno.env.get("INGEST_SECRET");
  if (!secret || req.headers.get("x-ingest-secret") !== secret) {
    return json({ error: "unauthenticated" }, 401);
  }

  let body: { dry_run?: boolean; refresh?: boolean };
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", resolveSecretKey(Deno.env.get));

  // Enrichment pass: canonical products with a GTIN-bearing variant and no
  // inci_raw yet. Refresh pass (`{"refresh": true}`): the already-enriched,
  // oldest-verified first — the reformulation watch.
  interface Candidate {
    id: string;
    inci_raw: string | null;
    variants: { gtin: string | null }[];
  }
  const selection = "id, inci_raw, variants!inner(gtin)";
  let candidates: Candidate[] | null;
  let candidatesError: unknown;
  if (body.refresh) {
    const result = await db.from("products").select(selection)
      .eq("scope", "canonical").is("merged_into", null).is("delisted_at", null)
      .not("variants.gtin", "is", null).not("inci_raw", "is", null)
      .order("last_verified", { ascending: true }).limit(MAX_PRODUCTS_PER_RUN);
    candidates = result.data as Candidate[] | null;
    candidatesError = result.error;
  } else {
    const result = await db.from("products").select(selection)
      .eq("scope", "canonical").is("merged_into", null).is("delisted_at", null)
      .not("variants.gtin", "is", null).is("inci_raw", null)
      .limit(MAX_PRODUCTS_PER_RUN);
    candidates = result.data as Candidate[] | null;
    candidatesError = result.error;
  }
  if (candidatesError) return json({ error: "candidate query failed" }, 500);

  const outcomes: { id: string; kind: string; detail?: string }[] = [];
  for (const candidate of candidates ?? []) {
    const gtin = (candidate.variants as { gtin: string | null }[])
      .map((v) => v.gtin).find((g) => g !== null);
    if (!gtin) continue;
    try {
      const fetched = await fetchINCI(gtin);
      const decision = plan(candidate.inci_raw, fetched);
      if (!body.dry_run) {
        switch (decision.kind) {
          case "enrich": {
            const { error } = await db
              .from("products")
              .update({ inci_raw: decision.inciRaw, last_verified: new Date().toISOString() })
              .eq("id", candidate.id);
            if (error) throw error;
            await attachChips(db, candidate.id, decision.chipSlugs);
            break;
          }
          case "queue_fork": {
            // Old keeps its chips and rankings, new starts clean, linked —
            // but creating the fork is the adjudication queue's decision,
            // with verb pre-set: a string mismatch is evidence, not a verdict.
            const { error } = await db.from("merge_candidates").insert({
              product_a: candidate.id,
              feed_row: { kind: "reformulation", fetched_inci: decision.fetchedRaw },
              state: "pending",
              verb: "fork",
            });
            if (error) throw error;
            break;
          }
          case "skip":
            break;
        }
      }
      outcomes.push({
        id: candidate.id,
        kind: decision.kind,
        detail: decision.kind === "skip" ? decision.reason : undefined,
      });
    } catch (error) {
      outcomes.push({ id: candidate.id, kind: "error", detail: String(error).slice(0, 120) });
    }
  }

  return json(
    { dry_run: body.dry_run ?? false, considered: candidates?.length ?? 0, outcomes },
    200,
  );
});
