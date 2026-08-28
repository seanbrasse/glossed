// dedupe_adjudicate — the pure half: what the model is asked, and what its
// verdict is allowed to do.
//
// PRD §16: the queue needs three verbs — merge / attach-as-variant / fork —
// because "merge or don't" forces variants and reformulations into the wrong
// bucket and corrupts the data either way. The model adjudicates within-brand
// pairs; one human reviews the middle band weekly; §17 says queue depth is
// the canary, and the tunable that moves it lives here as config.

export interface ProductRecord {
  id: string;
  name: string;
  brand_name: string;
  category_slug: string;
  variants: { shade_code: string | null; size_ml: number | null }[];
  inci_raw?: string | null;
}

export interface FeedRowRecord {
  name: string;
  brand: string;
  category_slug: string;
  shade_code?: string;
  size_ml?: number;
}

export type Verb = "merge" | "attach_variant" | "fork" | "unsure";

export interface Verdict {
  verb: Verb;
  confidence: number;
  reasoning: string;
}

/** Above this the verdict applies automatically; below it the pair stays
 * pending for the weekly human pass with the verdict recorded. Config, not
 * law — §17's canary (queue depth) is what tunes it. */
export const AUTO_APPLY_CONFIDENCE = 0.9;

/** How many pairs one run may send to the model. The spend cap: a run costs
 * at most this many calls, whatever the queue holds. */
export const MAX_CALLS_PER_RUN = 10;

/** The whole prompt. Deliberately only structured fields — never marketing
 * copy (PRD §15), and nothing the model could mistake for instructions. */
export function adjudicationPrompt(a: ProductRecord, counterpart: FeedRowRecord): string {
  const variants = a.variants
    .map((v) => [v.shade_code, v.size_ml ? `${v.size_ml}ml` : null].filter(Boolean).join(" "))
    .filter((s) => s.length > 0);
  return [
    "Two beauty-product records from the same brand may describe the same product.",
    "",
    `Catalog product: ${a.brand_name} — ${a.name} (category: ${a.category_slug})`,
    variants.length > 0
      ? `Known variants: ${variants.join(", ")}`
      : "Known variants: none recorded",
    "",
    `Feed row: ${counterpart.brand} — ${counterpart.name} (category: ${counterpart.category_slug})`,
    counterpart.shade_code ? `Feed shade: ${counterpart.shade_code}` : "",
    counterpart.size_ml ? `Feed size: ${counterpart.size_ml}ml` : "",
    "",
    "Decide the relationship:",
    "- merge: the same product and the same variant line — the feed row is a rename or restatement",
    "- attach_variant: the same product, a variant the catalog does not have (new shade or size)",
    '- fork: a successor or reformulation sold under a continuing name (e.g. "2027 formula")',
    "- unsure: a person should look",
    "",
    "Judge only from the fields above. A confident wrong merge corrupts two",
    "products' histories; when the fields cannot settle it, say unsure.",
  ].filter((line) => line !== "").join("\n");
}

/** What a verdict is allowed to do, given its confidence. */
export function disposition(verdict: Verdict): "auto_apply" | "hold_for_human" {
  if (verdict.verb === "unsure") return "hold_for_human";
  if (verdict.confidence < AUTO_APPLY_CONFIDENCE) return "hold_for_human";
  return "auto_apply";
}

/** The queue state a disposition writes. `auto_merged` is 0004's name for
 * "the machine decided"; held pairs stay pending so §17's canary counts them. */
export function stateFor(dispositionKind: "auto_apply" | "hold_for_human"): string {
  return dispositionKind === "auto_apply" ? "auto_merged" : "pending";
}
