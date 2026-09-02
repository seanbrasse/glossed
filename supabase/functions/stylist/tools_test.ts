import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  ARTIFACT_TOOLS,
  assembleReply,
  DATA_TOOLS,
  isAdult,
  MAX_CHIPS,
  MAX_TRANSCRIPT,
  NO_ANSWER_TEXT,
  renderContext,
  type StylistContext,
  systemPrompt,
  TOOLS,
  trimTranscript,
  validateArtifact,
} from "./tools.ts";

const ITEM = "11111111-1111-4111-8111-111111111111";
const PRODUCT = "22222222-2222-4222-8222-222222222222";
const LOOK = "33333333-3333-4333-8333-333333333333";
const COLLECTION = "44444444-4444-4444-8444-444444444444";
const STRANGER = "99999999-9999-4999-8999-999999999999";

const ctx: StylistContext = {
  profile: {
    skin_type: "dry",
    concerns: ["dryness"],
    hair_pattern: null,
    domains: ["skincare"],
    climate: null,
  },
  shelf: [{
    user_item_id: ITEM,
    product_id: PRODUCT,
    product_name: "niacinamide 10% + zinc",
    brand_name: "the ordinary",
    category_slug: "serum",
    category_label: "serums + actives",
    domain: "skincare",
    status: "own",
    rank_position: 1,
    ranked_in_category: 2,
  }],
  routines: [],
  collections: [{ id: COLLECTION, title: "holy grails only", item_n: 1 }],
  looks: [{ id: LOOK, caption: "golden hour", state: "draft", photo_n: 2 }],
};

Deno.test("the transcript is capped, ends on the user, and never starts on the assistant", () => {
  const turns = Array.from({ length: 30 }, (_, i) => ({
    role: (i % 2 === 0 ? "assistant" : "user") as "user" | "assistant",
    text: `t${i}`,
  }));
  const kept = trimTranscript(turns);
  assert(kept.length <= MAX_TRANSCRIPT);
  assertEquals(kept[0].role, "user");
  assertEquals(kept[kept.length - 1].role, "user");
});

Deno.test("blank and over-long messages are dropped or cut, never sent whole", () => {
  const kept = trimTranscript([{ role: "user", text: "   " }, {
    role: "user",
    text: "x".repeat(5000),
  }]);
  assertEquals(kept.length, 1);
  assertEquals(kept[0].text.length, 2000);
});

Deno.test("every tool has a schema, and every tool is either data or artifact — no orphans", () => {
  for (const t of TOOLS) {
    assert(t.name.length > 0 && t.description.length > 0);
    assertEquals(t.input_schema.type, "object");
    assert(DATA_TOOLS.has(t.name) || ARTIFACT_TOOLS.has(t.name), `${t.name} is in neither set`);
  }
  const chips = TOOLS.find((t) => t.name === "suggest_chips")!;
  const items = (chips.input_schema.properties as Record<string, { maxItems: number }>).chips;
  assertEquals(items.maxItems, MAX_CHIPS);
});

Deno.test("the prompt carries the rules that are not negotiable", () => {
  const p = systemPrompt();
  for (
    const must of [
      "do not diagnose",
      "never mention comedogenicity",
      "never say 'your match'",
      "UNTRUSTED",
      "never invent a product",
    ]
  ) {
    assert(p.toLowerCase().includes(must.toLowerCase()), `prompt lost: ${must}`);
  }
});

Deno.test("the context block is fenced, deterministic, and names every id the model may use", () => {
  const a = renderContext(ctx);
  const b = renderContext({ ...ctx, shelf: [...ctx.shelf].reverse() });
  assertEquals(a, b, "order of input must not change the block — it is a cache prefix");
  assert(a.startsWith("<context>") && a.endsWith("</context>"));
  for (const id of [ITEM, PRODUCT, LOOK, COLLECTION]) assert(a.includes(id));
  assert(a.includes("ranked #1 of 2 serums + actives"));
  assert(!/\d{4}-\d{2}-\d{2}T/.test(a), "no timestamps in a cache prefix");
});

Deno.test("a routine may only be built from the shelf, and says its gap", () => {
  const ok = validateArtifact(
    "propose_routine",
    {
      title: "glass skin, morning",
      slot: "am",
      targets: ["dryness"],
      steps: [{ user_item_id: ITEM, note: "wait 2 min" }, { user_item_id: ITEM }],
      gap: { category_label: "sunscreen", reason: "nothing on the shelf" },
    },
    ctx,
    new Map(),
  );
  assert(ok.ok);
  const block = ok.ok ? ok.block : null;
  assert(block?.type === "routine_draft");
  assertEquals(block.steps.length, 1, "a repeated item is one step");
  assertEquals(block.steps[0].brand_name, "the ordinary");
  assertEquals(block.gap?.category_label, "sunscreen");

  const bad = validateArtifact(
    "propose_routine",
    { title: "x", slot: "am", steps: [{ user_item_id: STRANGER }] },
    ctx,
    new Map(),
  );
  assert(!bad.ok);
  const badSlot = validateArtifact(
    "propose_routine",
    { title: "x", slot: "noon", steps: [{ user_item_id: ITEM }] },
    ctx,
    new Map(),
  );
  assert(!badSlot.ok);
});

Deno.test("a product list vouches only for the shelf and this turn's searches", () => {
  const searched = new Map([[STRANGER, {
    id: STRANGER,
    name: "cloud serum",
    brand_name: "somebrand",
    category_slug: "serum",
    domain: "skincare",
    n_face_offs: 12,
    catalog_image_key: null,
  }]]);
  const ok = validateArtifact(
    "show_products",
    { product_ids: [PRODUCT, STRANGER], reason: "two serums" },
    ctx,
    searched,
  );
  assert(ok.ok && ok.block?.type === "product_list");
  const list = ok.ok && ok.block?.type === "product_list" ? ok.block.products : [];
  assertEquals(list[0].on_shelf, true);
  assertEquals(list[0].rank_position, 1);
  assertEquals(list[1].on_shelf, false);
  assertEquals(list[1].n_face_offs, 12);

  const bad = validateArtifact(
    "show_products",
    { product_ids: ["55555555-5555-4555-8555-555555555555"], reason: "?" },
    ctx,
    new Map(),
  );
  assert(!bad.ok);
});

Deno.test("looks and collections must be the person's own", () => {
  assert(validateArtifact("reference_look", { look_id: LOOK }, ctx, new Map()).ok);
  assert(!validateArtifact("reference_look", { look_id: STRANGER }, ctx, new Map()).ok);
  assert(
    validateArtifact("reference_collection", { collection_id: COLLECTION }, ctx, new Map()).ok,
  );
  assert(!validateArtifact("reference_collection", { collection_id: STRANGER }, ctx, new Map()).ok);
});

Deno.test("chips are lowercased, deduplicated and capped", () => {
  const v = validateArtifact(
    "suggest_chips",
    { chips: ["Build My PM Routine", "build my pm routine", "a", "b", "c"] },
    ctx,
    new Map(),
  );
  assert(v.ok);
  assertEquals(v.ok ? v.chips : [], ["build my pm routine", "a", "b"]);
});

Deno.test("an empty answer is the honest line, and grounding names data tools only", () => {
  const r = assembleReply("   ", [], [], ["suggest_chips", "search_catalog", "search_catalog"], [
    "profile",
    "shelf",
  ]);
  assertEquals(r.text, NO_ANSWER_TEXT);
  assertEquals(r.grounded_in, ["profile", "shelf", "search_catalog"]);
  assertEquals(r.tools_used, ["suggest_chips", "search_catalog"]);
});

Deno.test("adults only, counted in full years from the first of the birth month", () => {
  const now = new Date(Date.UTC(2026, 8, 1));
  assert(isAdult("2008-09", now), "eighteen this month");
  assert(!isAdult("2008-10", now), "eighteen next month");
  assert(!isAdult(null, now));
  assert(!isAdult("garbage", now));
});
