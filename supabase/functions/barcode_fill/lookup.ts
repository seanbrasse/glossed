// barcode_fill — the pure half: what a Beauty API record becomes for the
// ladder, and when we are allowed to ask for one at all.
//
// Docs (read Aug 2026, thebeautyapi.com/docs): GET /v1/products/barcode/{code}
// resolves UPC-A / EAN-13 / GTIN-8/14 (regex ^[0-9]{8,14}$, zero-padded forms
// identical) to the full product record; 404 = no match, 403 = plan without
// barcode access, 429 = back off. Every request bills one call. The Sandbox
// tier is 100 calls/month, HARD CAP — the budget below keeps us under it with
// headroom, counting our own audit trail rather than trusting a remote meter.
//
// Deliberately NOT here: catalog inserts. Their `category` is domain-coarse
// ("skincare", never "serum"), and inventing a category_id is the
// wrong-franchise class of error (handoff §8). A hit pre-fills the create
// rung instead — the scanned GTIN rides the draft, and late-binding promotion
// (PersonalProductDraft's design) claims canonical identity later, honestly.

/// Everything the create rung can be pre-filled with, and nothing it would
/// have to guess at. `domain` is null when their category maps to nothing
/// in our enum — an unpicked domain beats a wrong one.
export interface FillSuggestion {
  found: boolean;
  brand?: string;
  name?: string;
  domain?: string | null;
  inci?: string | null;
}

/// The upstream record, to the depth we read it.
export interface BeautyAPIProduct {
  id?: string;
  brand?: string;
  name?: string;
  category?: string | null;
  ingredients?: { position?: number; label_name?: string }[];
}

const GTIN = /^[0-9]{8,14}$/;

/// The scanned code, normalized to digits, or null when it could never be a
/// GTIN. Mirrors the upstream contract exactly so a code we reject locally
/// is one they would reject too — a rejected-for-free call.
export function parseGTIN(raw: string): string | null {
  const digits = raw.replace(/[\s-]/g, "");
  return GTIN.test(digits) ? digits : null;
}

/// Their domain-coarse category → our `domain_enum`, or null. Suncare and
/// body live nearest skincare; anything unrecognized maps to nothing rather
/// than something.
export function mapDomain(category: string | null | undefined): string | null {
  switch ((category ?? "").toLowerCase()) {
    case "skincare":
    case "suncare":
    case "body & bath":
      return "skincare";
    case "haircare":
      return "haircare";
    case "makeup":
      return "makeup";
    case "fragrance":
      return "fragrance";
    default:
      return null;
  }
}

/// Label-order INCI, joined the way `products.inci_raw` stores it. Position
/// is the label's own order (their contract sorts it, but we sort again —
/// a comma list in the wrong order is a different formula). Capped like the
/// importers cap it.
export function joinINCI(
  ingredients: BeautyAPIProduct["ingredients"],
): string | null {
  const names = (ingredients ?? [])
    .filter((entry) => (entry.label_name ?? "").trim().length > 0)
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
    .map((entry) => (entry.label_name ?? "").trim());
  if (names.length === 0) return null;
  return names.join(", ").slice(0, 5000);
}

/// The month's spend limit: under the Sandbox's 100-call hard cap with
/// headroom for retries and clock skew. Counting our own audit rows is the
/// budget — the remote meter sends no usage headers at all.
export const MONTHLY_CALL_BUDGET = 95;

export function budgetAllows(callsThisMonth: number): boolean {
  return callsThisMonth < MONTHLY_CALL_BUDGET;
}

/// A 200 payload → what the ladder needs. Missing brand or name makes the
/// record useless for pre-fill, so it degrades to a miss — empty beats
/// fabricated, same rule as inci_enrich.
export function toSuggestion(record: BeautyAPIProduct): FillSuggestion {
  const brand = (record.brand ?? "").trim();
  const name = (record.name ?? "").trim();
  if (brand.length < 2 || name.length < 2) {
    return { found: false };
  }
  return {
    found: true,
    brand: brand.slice(0, 80),
    name: name.slice(0, 200),
    domain: mapDomain(record.category),
    inci: joinINCI(record.ingredients),
  };
}
