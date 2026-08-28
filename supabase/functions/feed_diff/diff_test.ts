import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  afterFailure,
  backoffSeconds,
  CANDIDATE_SIMILARITY,
  type FeedRow,
  gtin14,
  type KnownProduct,
  type KnownVariant,
  normalizeName,
  plan,
  similarity,
} from "./diff.ts";

// -- normalization: pinned to the same fixtures as the SQL side's pgTAP ------

Deno.test("normalization matches normalize_name(): apostrophes drop, separators space", () => {
  assertEquals(normalizeName("Pro Filt'r Soft Matte"), "pro filtr soft matte");
  assertEquals(normalizeName("Vitamin-C 10%"), "vitamin c 10");
  assertEquals(normalizeName("  Rare   Beauty  "), "rare beauty");
});

// -- GTIN-14: a US scan and a EU feed row are the same code ------------------

Deno.test("UPC-A and EAN-13 for the same product land on one GTIN-14", () => {
  assertEquals(gtin14("810086012343"), "00810086012343");
  assertEquals(gtin14("0810086012343"), "00810086012343");
});

Deno.test("a code that is not a GTIN is no code at all", () => {
  assertEquals(gtin14("not-a-code"), null);
  assertEquals(gtin14("1234567"), null); // too short
  assertEquals(gtin14(""), null);
  assertEquals(gtin14(undefined), null);
});

// -- planning ----------------------------------------------------------------

const VARIANT: KnownVariant = {
  variant_id: "v-1",
  product_id: "p-1",
  gtin: "0810086012343",
};
const byGTIN = new Map([["00810086012343", VARIANT]]);
const brandBlock: KnownProduct[] = [
  { product_id: "p-1", brand_id: "b-1", normalized_name: "pro filtr soft matte" },
];

const row = (overrides: Partial<FeedRow>): FeedRow => ({
  brand: "fenty beauty",
  name: "pro filt'r soft matte",
  category_slug: "foundation",
  domain: "makeup",
  ...overrides,
});

Deno.test("a GTIN match updates the variant, whatever the name says", () => {
  // Feeds rename products constantly; the code is the identity.
  const decision = plan(
    row({ gtin: "810086012343", name: "PRO FILT'R Soft Matte NEW" }),
    byGTIN,
    [],
  );
  assertEquals(decision.kind, "update_variant");
});

Deno.test("a delisting needs a known variant and writes nothing otherwise", () => {
  assertEquals(
    plan(row({ gtin: "810086012343", delisted: true }), byGTIN, []).kind,
    "delist_variant",
  );
  assertEquals(plan(row({ gtin: "999999999999", delisted: true }), byGTIN, []).kind, "skip");
});

Deno.test("no GTIN, similar same-brand name: a merge candidate, never a write", () => {
  // PRD §16 needs three verbs, so the ambiguous case goes to the queue —
  // writing a new product here would manufacture the duplicates PR 2 prevents.
  const decision = plan(row({ name: "pro filtr soft matte foundation" }), new Map(), brandBlock);
  assertEquals(decision.kind, "queue_candidate");
});

Deno.test("no GTIN, nothing similar in the brand block: a new product", () => {
  const decision = plan(row({ name: "gloss bomb universal lip luminizer" }), new Map(), brandBlock);
  assertEquals(decision.kind, "insert_product");
});

Deno.test("a row without a brand and a name is noise, not a product", () => {
  assertEquals(plan(row({ brand: " " }), byGTIN, brandBlock).kind, "skip");
  assertEquals(plan(row({ name: "" }), byGTIN, brandBlock).kind, "skip");
});

// -- similarity band ---------------------------------------------------------

Deno.test("the band separates a rename from a different product", () => {
  const rename = similarity("pro filtr soft matte", "pro filtr soft matte foundation");
  const different = similarity("pro filtr soft matte", "gloss bomb universal lip luminizer");
  assert(rename >= CANDIDATE_SIMILARITY, `rename scored ${rename}`);
  assert(different < CANDIDATE_SIMILARITY, `different product scored ${different}`);
});

Deno.test("identical names are 1, unrelated names near 0", () => {
  assertEquals(similarity("blush", "blush"), 1);
  // "blush"/"shampoo" share the bigram "sh" — 0.2, nowhere near the band.
  assert(similarity("blush", "shampoo") < CANDIDATE_SIMILARITY / 2);
});

// -- the job state machine ---------------------------------------------------

Deno.test("backoff doubles from a minute and failure dead-letters at the cap", () => {
  assertEquals(backoffSeconds(1), 60);
  assertEquals(backoffSeconds(2), 120);
  assertEquals(backoffSeconds(4), 480);
  assertEquals(afterFailure(1), "queued");
  assertEquals(afterFailure(4), "queued");
  assertEquals(afterFailure(5), "dead");
});
