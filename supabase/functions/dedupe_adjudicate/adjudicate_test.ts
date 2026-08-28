import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  adjudicationPrompt,
  AUTO_APPLY_CONFIDENCE,
  disposition,
  type ProductRecord,
  stateFor,
} from "./adjudicate.ts";

const product: ProductRecord = {
  id: "p-1",
  name: "pineapple refresh",
  brand_name: "rhode",
  category_slug: "cleanser",
  variants: [{ shade_code: null, size_ml: 150 }],
};

Deno.test("the prompt carries only structured fields", () => {
  const prompt = adjudicationPrompt(product, {
    name: "pineapple refresh cleanser",
    brand: "rhode",
    category_slug: "cleanser",
    size_ml: 150,
  });
  assertStringIncludes(prompt, "rhode — pineapple refresh");
  assertStringIncludes(prompt, "150ml");
  assertStringIncludes(prompt, "say unsure");
  // No verb the model could read as an instruction to write anywhere.
  assert(!prompt.includes("INSERT"), "nothing SQL-shaped");
});

Deno.test("unsure always holds, whatever the confidence", () => {
  assertEquals(disposition({ verb: "unsure", confidence: 0.99, reasoning: "" }), "hold_for_human");
});

Deno.test("confidence below the band holds; at or above it applies", () => {
  assertEquals(
    disposition({ verb: "merge", confidence: AUTO_APPLY_CONFIDENCE - 0.01, reasoning: "" }),
    "hold_for_human",
  );
  assertEquals(
    disposition({ verb: "attach_variant", confidence: AUTO_APPLY_CONFIDENCE, reasoning: "" }),
    "auto_apply",
  );
});

Deno.test("held pairs stay pending so the queue-depth canary counts them", () => {
  assertEquals(stateFor("hold_for_human"), "pending");
  assertEquals(stateFor("auto_apply"), "auto_merged");
});
