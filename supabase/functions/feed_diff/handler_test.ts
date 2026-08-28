import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1";
import { type FeedRow, gtin14, type KnownProduct, type KnownVariant, plan } from "./diff.ts";
import { resolveSecretKey } from "./index.ts";

// -- the credential contract -------------------------------------------------
// The modern env is a JSON dictionary (SUPABASE_SECRET_KEYS); the legacy
// single value still exists on older stacks. Read either, prefer the modern.

Deno.test("the modern secret-keys dictionary wins", () => {
  const env = (name: string) =>
    name === "SUPABASE_SECRET_KEYS" ? '{"default":"sb_secret_modern"}' : "legacy";
  assertEquals(resolveSecretKey(env), "sb_secret_modern");
});

Deno.test("the legacy variable still works", () => {
  const env = (name: string) => name === "SUPABASE_SERVICE_ROLE_KEY" ? "legacy_key" : undefined;
  assertEquals(resolveSecretKey(env), "legacy_key");
});

Deno.test("no credential is an error, not an empty string", () => {
  assertThrows(() => resolveSecretKey(() => undefined));
});

// -- the fixture feed against the local seed's shape -------------------------
// The fixture is built so one run exercises every plan kind. This test pins
// that property: if someone trims the fixture, the pipeline's dry run stops
// proving what it claims to prove.

const fixture = JSON.parse(
  await Deno.readTextFile(new URL("./fixture_feed.json", import.meta.url)),
) as { rows: FeedRow[] };

// What the seed holds, as the planner sees it (ids abridged).
const seedVariants = new Map<string, KnownVariant>([
  [gtin14("0810086012343")!, { variant_id: "v-220", product_id: "p-filtr", gtin: "0810086012343" }],
  [gtin14("0810086012350")!, { variant_id: "v-240", product_id: "p-filtr", gtin: "0810086012350" }],
]);
const rhodeBlock: KnownProduct[] = [
  { product_id: "p-pineapple", brand_id: "b-rhode", normalized_name: "pineapple refresh" },
];

Deno.test("one fixture run exercises every plan kind", () => {
  const kinds = fixture.rows.map((row) => {
    const block = row.brand.trim() === "rhode" ? rhodeBlock : [];
    return plan(row, seedVariants, block).kind;
  });
  assert(kinds.includes("update_variant"), "a GTIN update");
  assert(kinds.includes("delist_variant"), "a delisting");
  assert(kinds.includes("queue_candidate"), "a rename that must queue");
  assert(kinds.includes("insert_product"), "a genuinely new product");
  assert(kinds.includes("skip"), "a noise row");
});
