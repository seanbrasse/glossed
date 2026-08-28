// feed_diff — the pure half: what a feed row means for the catalog.
//
// PRD §15: "a licensed snapshot is a one-time backfill, retailer feeds are the
// heartbeat, users are the tail. Nothing in the steady state is metered per
// user." This module decides, row by row, what the heartbeat writes — and it
// is pure so every decision is testable without a database.
//
// The handler (index.ts) owns transport: claiming the job, reading current
// state, applying the plan, finishing or dead-lettering the job.

/** One row of a retailer feed, already parsed. */
export interface FeedRow {
  gtin?: string;
  brand: string;
  name: string;
  category_slug: string;
  domain: "makeup" | "skincare" | "haircare" | "fragrance";
  shade_code?: string;
  size_ml?: number;
  price_cents?: number;
  currency?: string;
  availability?: string;
  delisted?: boolean;
}

/** What the catalog already holds, as the planner needs it. */
export interface KnownVariant {
  variant_id: string;
  product_id: string;
  gtin: string | null;
}

export interface KnownProduct {
  product_id: string;
  brand_id: string;
  normalized_name: string;
}

/** One decision per feed row. Applying them is the handler's job. */
export type Plan =
  | { kind: "update_variant"; variantID: string; row: FeedRow }
  | { kind: "delist_variant"; variantID: string }
  // Same brand, similar name, no GTIN match: a candidate for the merge queue,
  // never an automatic write — §16's three verbs need a human or an
  // adjudicator, and that is PR 2. Writing it as a new product here would
  // manufacture the duplicates PR 2 exists to prevent.
  | { kind: "queue_candidate"; productID: string; row: FeedRow; similarity: number }
  | { kind: "insert_product"; row: FeedRow }
  | { kind: "skip"; reason: string };

// Mirrors the database's normalize_name(): apostrophes drop ("filt'r" is one
// word), every other run of non-alphanumerics becomes one space. The pgTAP
// suite pins the SQL side; diff_test.ts pins this one to the same fixtures.
export function normalizeName(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/['’ʼ]/g, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

// GTINs arrive as UPC-A (12), EAN-13, or GTIN-14. Everything is compared at 14
// digits, zero-padded — the same product scans as 12 digits in the US and 13
// in Europe, and comparing raw strings reports a stocked product as missing
// (GLO-58's bug, kept out of this code path from the start).
export function gtin14(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const digits = raw.replace(/\D/g, "");
  if (digits.length < 8 || digits.length > 14) return null;
  return digits.padStart(14, "0");
}

/** Dice coefficient over character bigrams — the trigram-ish similarity the
 * fallback match uses. Not pg_trgm, and does not need to be: this band only
 * decides whether a row *becomes a merge candidate*, and the adjudicator
 * re-reads both sides before anything merges. */
export function similarity(a: string, b: string): number {
  if (a === b) return 1;
  if (a.length < 2 || b.length < 2) return 0;
  const bigrams = (s: string) => {
    const grams = new Map<string, number>();
    for (let i = 0; i < s.length - 1; i++) {
      const g = s.slice(i, i + 2);
      grams.set(g, (grams.get(g) ?? 0) + 1);
    }
    return grams;
  };
  const ga = bigrams(a);
  const gb = bigrams(b);
  let shared = 0;
  for (const [gram, count] of ga) shared += Math.min(count, gb.get(gram) ?? 0);
  return (2 * shared) / (a.length - 1 + b.length - 1);
}

/** Above this, a same-brand name is probably the same product and goes to the
 * merge queue; below it, it is a new product. Config, not law — the auto-band
 * thresholds are tunable and §17 says the merge-queue depth is the canary. */
export const CANDIDATE_SIMILARITY = 0.55;

/** What this feed row means, given what the catalog already knows.
 *
 * `variantsByGTIN` is keyed by `gtin14`; `brandProducts` is the same-brand
 * block (block-and-match: candidates are only ever sought within the brand). */
export function plan(
  row: FeedRow,
  variantsByGTIN: Map<string, KnownVariant>,
  brandProducts: KnownProduct[],
): Plan {
  if (!row.brand.trim() || !row.name.trim()) {
    return { kind: "skip", reason: "a row without a brand and a name is noise" };
  }

  const code = gtin14(row.gtin);
  const known = code ? variantsByGTIN.get(code) : undefined;
  if (known) {
    // The exact match. Price, availability and delisting ride on the variant.
    return row.delisted
      ? { kind: "delist_variant", variantID: known.variant_id }
      : { kind: "update_variant", variantID: known.variant_id, row };
  }
  if (row.delisted) {
    // A delisting for something we never stocked writes nothing.
    return { kind: "skip", reason: "delisting an unknown variant" };
  }

  const name = normalizeName(row.name);
  let best: { product: KnownProduct; score: number } | null = null;
  for (const product of brandProducts) {
    const score = similarity(name, product.normalized_name);
    if (score >= CANDIDATE_SIMILARITY && (!best || score > best.score)) {
      best = { product, score };
    }
  }
  if (best) {
    return {
      kind: "queue_candidate",
      productID: best.product.product_id,
      row,
      similarity: best.score,
    };
  }
  return { kind: "insert_product", row };
}

// ---------------------------------------------------------------------------
// The job state machine. ingest_jobs rows: queued → running → done | failed →
// (retry with backoff) → dead. The table's shape is migration 0004's; these
// rules are the only place the transitions live.
// ---------------------------------------------------------------------------

export const MAX_ATTEMPTS = 5;

/** Exponential backoff with a floor, in seconds: 60, 120, 240, 480. */
export function backoffSeconds(attempts: number): number {
  return 60 * 2 ** Math.max(0, Math.min(attempts - 1, 6));
}

/** Where a failed run goes: back in the queue with backoff, or dead. */
export function afterFailure(attempts: number): "queued" | "dead" {
  return attempts >= MAX_ATTEMPTS ? "dead" : "queued";
}
