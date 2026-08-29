// The pure half of barcode_fill, tested to its contract: the upstream regex,
// the domain mapping's refusal to guess, label-order INCI, and the budget
// arithmetic that keeps the Sandbox hard cap unreachable.

import { assertEquals } from "jsr:@std/assert@1";
import {
  budgetAllows,
  joinINCI,
  mapDomain,
  MONTHLY_CALL_BUDGET,
  parseGTIN,
  toSuggestion,
} from "./lookup.ts";

Deno.test("parseGTIN mirrors the upstream contract exactly", () => {
  assertEquals(parseGTIN("769915195941"), "769915195941"); // UPC-A
  assertEquals(parseGTIN("0769915195941"), "0769915195941"); // EAN-13 pad
  assertEquals(parseGTIN(" 769-9151 95941 "), "769915195941"); // scanner noise
  assertEquals(parseGTIN("1234567"), null); // seven: too short
  assertEquals(parseGTIN("123456789012345"), null); // fifteen: too long
  assertEquals(parseGTIN("not-a-code"), null);
  assertEquals(parseGTIN(""), null);
});

Deno.test("mapDomain never guesses", () => {
  assertEquals(mapDomain("skincare"), "skincare");
  assertEquals(mapDomain("Suncare"), "skincare");
  assertEquals(mapDomain("body & bath"), "skincare");
  assertEquals(mapDomain("haircare"), "haircare");
  assertEquals(mapDomain("makeup"), "makeup");
  assertEquals(mapDomain("fragrance"), "fragrance");
  // Unknown maps to nothing rather than something — an unpicked domain in
  // the create rung beats a wrong one on a canonical row later.
  assertEquals(mapDomain("other"), null);
  assertEquals(mapDomain(null), null);
  assertEquals(mapDomain(undefined), null);
});

Deno.test("joinINCI keeps the label's own order", () => {
  const inci = joinINCI([
    { position: 2, label_name: "Zinc PCA 1.0%" },
    { position: 1, label_name: "Niacinamide 10.0%" },
    { position: 3, label_name: " Aqua " },
  ]);
  assertEquals(inci, "Niacinamide 10.0%, Zinc PCA 1.0%, Aqua");
});

Deno.test("joinINCI says nothing when there is nothing", () => {
  assertEquals(joinINCI([]), null);
  assertEquals(joinINCI(undefined), null);
  assertEquals(joinINCI([{ position: 1, label_name: "  " }]), null);
});

Deno.test("a record without an identity degrades to a miss", () => {
  // Empty beats fabricated — a pre-fill needs both halves of the identity.
  assertEquals(toSuggestion({ brand: "", name: "Some Serum" }).found, false);
  assertEquals(toSuggestion({ brand: "The Ordinary", name: "" }).found, false);
  assertEquals(toSuggestion({}).found, false);
});

Deno.test("a full record becomes the create rung's pre-fill", () => {
  const suggestion = toSuggestion({
    id: "06d9476a-397b-5f61-abc8-640b30a9ae23",
    brand: "The Ordinary",
    name: "Niacinamide 10% + Zinc 1%",
    category: "skincare",
    ingredients: [
      { position: 1, label_name: "Niacinamide 10.0%" },
      { position: 2, label_name: "Zinc PCA 1.0%" },
    ],
  });
  assertEquals(suggestion.found, true);
  assertEquals(suggestion.brand, "The Ordinary");
  assertEquals(suggestion.name, "Niacinamide 10% + Zinc 1%");
  assertEquals(suggestion.domain, "skincare");
  assertEquals(suggestion.inci, "Niacinamide 10.0%, Zinc PCA 1.0%");
});

Deno.test("the budget stops under the Sandbox hard cap, with headroom", () => {
  assertEquals(budgetAllows(0), true);
  assertEquals(budgetAllows(MONTHLY_CALL_BUDGET - 1), true);
  assertEquals(budgetAllows(MONTHLY_CALL_BUDGET), false);
  assertEquals(budgetAllows(MONTHLY_CALL_BUDGET + 40), false);
  // The point of 95: even a burst of in-flight retries cannot reach 100.
  assertEquals(MONTHLY_CALL_BUDGET < 100, true);
});
