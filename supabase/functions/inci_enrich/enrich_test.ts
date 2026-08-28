import { assert, assertEquals } from "jsr:@std/assert@1";
import { deriveChipSlugs, isReformulation, plan } from "./enrich.ts";

// -- normalization -----------------------------------------------------------

Deno.test("case and spacing do not make a reformulation", () => {
  assert(!isReformulation("Aqua, Glycerin,  Niacinamide.", "aqua,glycerin,niacinamide"));
});

Deno.test("a reorder IS a reformulation — INCI order is concentration order", () => {
  assert(isReformulation("aqua, glycerin, niacinamide", "aqua, niacinamide, glycerin"));
});

Deno.test("an added ingredient is a reformulation", () => {
  assert(isReformulation("aqua, glycerin", "aqua, glycerin, parfum"));
});

// -- derivations: presence/absence of structured ingredients, never claims ---

Deno.test("no parfum, no fragrance markers: fragrance-free derives", () => {
  assertEquals(deriveChipSlugs("aqua, glycerin, niacinamide"), [
    "fragrance-free",
    "silicone-free",
  ]);
});

Deno.test("parfum anywhere kills fragrance-free", () => {
  assertEquals(deriveChipSlugs("aqua, parfum, glycerin"), ["silicone-free"]);
  assertEquals(deriveChipSlugs("aqua, fragrance, glycerin"), ["silicone-free"]);
});

Deno.test("a -cone or -siloxane kills silicone-free", () => {
  assertEquals(deriveChipSlugs("aqua, dimethicone"), ["fragrance-free"]);
  assertEquals(deriveChipSlugs("aqua, cyclopentasiloxane"), ["fragrance-free"]);
});

Deno.test("limonene is not a fragrance marker and lanolin is not a silicone", () => {
  // Substring matching would false-positive both families; the derivations
  // match whole markers and suffixes on whole words.
  assertEquals(deriveChipSlugs("aqua, limonene, lanolin"), [
    "fragrance-free",
    "silicone-free",
  ]);
});

// -- the pass ----------------------------------------------------------------

Deno.test("no source, no fabrication — empty beats fabricated", () => {
  assertEquals(plan(null, null).kind, "skip");
  assertEquals(plan(null, "  ").kind, "skip");
});

Deno.test("first sight enriches; unchanged refresh skips; change queues a fork", () => {
  const first = plan(null, "aqua, glycerin");
  assertEquals(first.kind, "enrich");
  assertEquals(plan("aqua, glycerin", "Aqua, Glycerin").kind, "skip");
  assertEquals(plan("aqua, glycerin", "aqua, glycerin, retinol").kind, "queue_fork");
});
