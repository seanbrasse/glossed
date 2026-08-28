// inci_enrich — the pure half: what an INCI string tells us, and when a
// changed one is a reformulation.
//
// PRD §15's rules, encoded rather than remembered:
//   - attribute chips derive ONLY from structured fields — the ingredient
//     list is structured; marketing copy never is, and importing a claim
//     like "suitable for all skin types" would poison the one thing that
//     makes our filters better than a retailer's.
//   - enrichment happens once per product, cached forever; a refresh only
//     COMPARES — "reformulation is a string comparison, not a purchase".
//   - comedogenicity ships in the data and is never surfaced (§10: using it
//     would undercut the receipts-based positioning). It is deliberately not
//     derived here at all.

/** One ingredient list, normalized for comparison: lowercase, whitespace
 * collapsed, trailing punctuation dropped. Order is preserved — INCI order
 * is concentration order and a reorder IS a reformulation. */
export function normalizeINCI(raw: string): string {
  return raw
    .toLowerCase()
    .split(",")
    .map((part) => part.replace(/[.\s]+$/g, "").replace(/^\s+/g, "").replace(/\s+/g, " "))
    .filter((part) => part.length > 0)
    .join(", ");
}

/** A changed list queues a fork (old keeps its chips and rankings, new
 * starts clean, linked). Same list, differently spaced or cased, is not a
 * reformulation — that is the point of comparing normalized forms. */
export function isReformulation(storedRaw: string, fetchedRaw: string): boolean {
  return normalizeINCI(storedRaw) !== normalizeINCI(fetchedRaw);
}

/** The chip derivations. Each is a *absence or presence of a structured
 * ingredient*, never a judgement. The slugs are the seeded vocabulary —
 * deriving a chip that is not in `attribute_chips` is a vocabulary PR, not
 * an ingest side effect, so unknown derivations are dropped by the caller
 * (it inserts by slug lookup and a missing slug inserts nothing). */
const FRAGRANCE_MARKERS = ["parfum", "fragrance", "aroma"];
const SILICONE_SUFFIXES = ["cone", "conol", "siloxane", "silsesquioxane"];

export function deriveChipSlugs(inciRaw: string): string[] {
  const ingredients = normalizeINCI(inciRaw).split(", ");
  const slugs: string[] = [];

  if (!ingredients.some((i) => FRAGRANCE_MARKERS.some((m) => i === m || i.startsWith(m + " ")))) {
    slugs.push("fragrance-free");
  }
  if (
    !ingredients.some((ingredient) =>
      ingredient.split(/[\s-]/).some((word) => SILICONE_SUFFIXES.some((s) => word.endsWith(s)))
    )
  ) {
    slugs.push("silicone-free");
  }
  return slugs;
}

/** What one enrichment pass decides for one product. */
export type EnrichPlan =
  | { kind: "enrich"; inciRaw: string; chipSlugs: string[] }
  | { kind: "queue_fork"; storedRaw: string; fetchedRaw: string }
  | { kind: "skip"; reason: string };

export function plan(storedRaw: string | null, fetchedRaw: string | null): EnrichPlan {
  if (!fetchedRaw || normalizeINCI(fetchedRaw).length === 0) {
    // "Empty beats fabricated" — the AI rule, applied to sources too. A
    // product no source can describe stays undescribed.
    return { kind: "skip", reason: "no source has an ingredient list" };
  }
  if (storedRaw && normalizeINCI(storedRaw).length > 0) {
    if (isReformulation(storedRaw, fetchedRaw)) {
      return { kind: "queue_fork", storedRaw, fetchedRaw };
    }
    return { kind: "skip", reason: "already enriched, unchanged" };
  }
  return { kind: "enrich", inciRaw: fetchedRaw, chipSlugs: deriveChipSlugs(fetchedRaw) };
}
