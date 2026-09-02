import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  buildRoutine,
  type CategoryRef,
  cohortScope,
  detectIntent,
  type FetchResult,
  missingCategories,
  OPEN_WITHOUT_MODEL,
  type PlanInput,
  planTurn,
} from "./plan.ts";
import { MAX_CHIPS, type ShelfItem, type StylistContext } from "./tools.ts";

const ids = (n: number) =>
  `${String(n).repeat(8)}-${String(n).repeat(4)}-4${String(n).repeat(3)}-8${String(n).repeat(3)}-${
    String(n).repeat(12)
  }`;

function item(
  n: number,
  slug: string,
  label: string,
  name: string,
  extra: Partial<ShelfItem> = {},
): ShelfItem {
  return {
    user_item_id: ids(n),
    product_id: ids(n + 5),
    product_name: name,
    brand_name: "brand",
    category_slug: slug,
    category_label: label,
    domain: slug === "styler" ? "haircare" : "skincare",
    status: "own",
    rank_position: null,
    ranked_in_category: 0,
    benefit_line: null,
    catalog_image_key: null,
    ...extra,
  };
}

// maya's seed shelf, in shape: a cleanser, a serum, a styler — no moisturizer, no sunscreen.
const shelf: ShelfItem[] = [
  item(1, "cleanser", "cleanser", "pineapple refresh"),
  item(2, "serum", "serums + actives", "niacinamide 10% + zinc", {
    rank_position: 1,
    ranked_in_category: 2,
  }),
  item(3, "serum", "serums + actives", "cloud serum", { rank_position: 2, ranked_in_category: 2 }),
  item(4, "styler", "stylers", "weightless curl cream"),
];

const categories: CategoryRef[] = [
  { id: ids(6), slug: "cleanser", label: "cleanser", domain: "skincare" },
  { id: ids(7), slug: "serum", label: "serums + actives", domain: "skincare" },
  { id: ids(8), slug: "moisturizer", label: "moisturizer", domain: "skincare" },
  { id: ids(9), slug: "sunscreen", label: "sun", domain: "skincare" },
  { id: ids(0), slug: "styler", label: "stylers", domain: "haircare" },
];

const ctx: StylistContext = {
  profile: {
    skin_type: null,
    concerns: ["dryness"],
    hair_pattern: "3b",
    domains: ["skincare"],
    climate: null,
  },
  shelf,
  routines: [{
    id: ids(1),
    title: "morning glass skin",
    slot: "am",
    steps: [{ user_item_id: ids(1), note: null }],
  }],
  collections: [],
  looks: [],
};

const input: PlanInput = { ctx, categories, hasShadeAnchor: false };

Deno.test("the words pick the intent, and the slot and domain ride on them", () => {
  assertEquals(detectIntent("build me a morning routine from what I own", input), {
    kind: "routine",
    slot: "am",
    domain: "skincare",
  });
  assertEquals(detectIntent("what's my wash day routine", input), {
    kind: "routine",
    slot: "wash_day",
    domain: "haircare",
  });
  assertEquals(detectIntent("pm routine please", input).kind, "routine");
  assertEquals((detectIntent("pm routine please", input) as { slot: string }).slot, "pm");
  assertEquals(detectIntent("what am I missing for dryness", input).kind, "missing");
  assertEquals(detectIntent("what should I try next", input).kind, "try_next");
  assertEquals(detectIntent("compare my two serums", input), {
    kind: "compare",
    category_slug: "serum",
  });
  assertEquals(
    detectIntent("can I use niacinamide together with my cleanser", input).kind,
    "clash",
  );
  assertEquals(detectIntent("what does niacinamide do", input), {
    kind: "about_item",
    user_item_id: ids(2),
  });
  assertEquals(detectIntent("hi", input).kind, "greeting");
  assertEquals(detectIntent("what's the capital of peru", input).kind, "open");
});

Deno.test("anything medical is caught before any other rule, routine word or not", () => {
  assertEquals(detectIntent("routine for my rash", input).kind, "medical");
  assertEquals(detectIntent("I was prescribed tretinoin, what order", input).kind, "medical");
});

Deno.test("a morning routine is the shelf in order, one per category, the best rank leading, and names one gap", () => {
  const r = buildRoutine("am", "skincare", ctx);
  assert(r);
  assertEquals(r.title, "morning skincare");
  assertEquals(r.slot, "am");
  assertEquals(r.steps.map((s) => s.product_name), ["pineapple refresh", "niacinamide 10% + zinc"]);
  assert(r.steps.every((s) => shelf.some((i) => i.user_item_id === s.user_item_id)));
  assertEquals(r.targets, ["dryness"]);
  // moisturizer is the first essential missing; sunscreen waits its turn
  assertEquals(r.gap?.category_label, "moisturizer");
});

Deno.test("the wash day comes from the haircare shelf, and an empty domain builds nothing", () => {
  const wash = buildRoutine("wash_day", "haircare", ctx);
  assert(wash);
  assertEquals(wash.steps.map((s) => s.product_name), ["weightless curl cream"]);
  assertEquals(wash.gap?.category_label, "shampoo");
  assertEquals(buildRoutine("am", "makeup", ctx), null);
});

Deno.test("a routine turn needs no fetch, says its gap, and offers three chips or fewer", () => {
  const plan = planTurn("build me a morning routine", input);
  assertEquals(plan.fetches, []);
  const reply = plan.finish([]);
  assertEquals(reply.blocks.length, 1);
  assert(reply.text.includes("the one gap is moisturizer"));
  assert(reply.text.includes("morning glass skin"), "names the routine already kept for that slot");
  assert(reply.chips.length <= MAX_CHIPS);
  assertEquals(reply.grounded_in, ["profile", "shelf", "routines"]);
  assert(!reply.tools_used.includes("model"));
});

Deno.test("the gaps are the concern's wants less the shelf, and the cohort is chosen from what we know", () => {
  assertEquals(missingCategories(ctx), ["moisturizer", "sunscreen"]);
  const basics = missingCategories({ ...ctx, profile: { ...ctx.profile, concerns: [] } });
  assertEquals(basics, ["moisturizer", "sunscreen"]);
  assertEquals(cohortScope(categories[2], input), "all", "skincare has no cohort");
  assertEquals(cohortScope(categories[4], input), "yours", "haircare resolves by hair pattern");
  assertEquals(
    cohortScope(categories[4], {
      ...input,
      ctx: { ...ctx, profile: { ...ctx.profile, hair_pattern: null } },
    }),
    "all",
  );
});

Deno.test("a missing turn fetches one leaderboard per gap and renders rows with whose n they carry", () => {
  const plan = planTurn("what am I missing", input);
  assertEquals(plan.fetches.map((f) => f.kind === "leaderboard" && f.category.slug), [
    "moisturizer",
    "sunscreen",
  ]);
  const results: FetchResult[] = [
    {
      fetch: plan.fetches[0],
      rows: [{
        id: ids(3),
        name: "you",
        brand_name: "glossier",
        category_slug: "moisturizer",
        domain: "skincare",
        n_face_offs: 12,
        catalog_image_key: null,
        n_users: 9,
        mean_percentile: 0.8,
      }],
    },
    { fetch: plan.fetches[1], rows: [] },
  ];
  const reply = plan.finish(results);
  assert(reply.text.includes("no moisturizer or sun"));
  assert(reply.text.includes("no receipts yet for sun"));
  assertEquals(reply.blocks.length, 1);
  const block = reply.blocks[0];
  assert(block.type === "product_list");
  assertEquals(block.products[0].basis_label, "face-offs in moisturizer, everyone");
  assertEquals(block.products[0].basis_n, 12);
  assertEquals(block.products[0].on_shelf, false);
  assert(reply.grounded_in.includes("leaderboard"));
});

Deno.test("try next merges the crosswalk and discover, dedupes, and says how many carry receipts", () => {
  const plan = planTurn("what should I try next", input);
  const [discover, crosswalk] = plan.fetches;
  const hit = (n: number, extra: Record<string, unknown>) => ({
    id: ids(n),
    name: `p${n}`,
    brand_name: "b",
    category_slug: "serum",
    domain: "skincare",
    n_face_offs: 3,
    catalog_image_key: null,
    ...extra,
  });
  const reply = plan.finish([
    {
      fetch: discover,
      rows: [
        hit(4, { basis: "taste", basis_n: 3 }),
        hit(5, { basis: "exploration", basis_n: 0 }),
        hit(4, { basis: "everyone", basis_n: 9 }),
      ],
    },
    { fetch: crosswalk, rows: [hit(9, { anchor_label: "230", n: 7 })] },
  ]);
  const block = reply.blocks[0];
  assert(block.type === "product_list");
  assertEquals(block.products.map((p) => p.product_id), [ids(9), ids(4), ids(5)]);
  assertEquals(block.products[0].basis_label, "people who wear 230 also wear it");
  assertEquals(block.products[2].basis_n, 0);
  assert(reply.text.startsWith("from your logs and people like you — 2 with receipts, 1 without."));
});

Deno.test("try next with nothing to show says so rather than inventing a pick", () => {
  const plan = planTurn("recommend me something", input);
  const reply = plan.finish(plan.fetches.map((fetch) => ({ fetch, rows: [] })));
  assertEquals(reply.blocks, []);
  assert(reply.text.includes("nothing with receipts yet"));
});

Deno.test("compare reads the person's own ranks; one item or none is said plainly", () => {
  const two = planTurn("compare my serums", input).finish([]);
  assert(
    two.text.startsWith(
      "you ranked niacinamide 10% + zinc #1 of 2 in serums + actives; cloud serum sits #2.",
    ),
  );
  const one = planTurn("which of my cleansers is better", input).finish([]);
  assert(one.text.startsWith("one cleanser on your shelf"));
  const none = planTurn("compare my sunscreens", input).finish([]);
  assertEquals(none.text, "no sun on your shelf yet.");
  const unnamed = planTurn("compare", input).finish([]);
  assert(
    unnamed.text.includes("serums + actives"),
    "the category owned most is compared when none is named",
  );
});

Deno.test("about an item: the catalog's line, the rank, and the routines it sits in", () => {
  const withLine: PlanInput = {
    ...input,
    ctx: {
      ...ctx,
      shelf: shelf.map((s) =>
        s.user_item_id === ids(1) ? { ...s, benefit_line: "a gentle gel" } : s
      ),
    },
  };
  const reply = planTurn("tell me about pineapple refresh", withLine).finish([]);
  assert(reply.text.includes("the catalog says: a gentle gel."));
  assert(reply.text.includes("haven't ranked it yet"));
  assert(reply.text.includes('"morning glass skin"'));
  assertEquals(reply.blocks.length, 1);
});

Deno.test("clash, medical, greeting and open answer from rules alone and never claim a model", () => {
  for (const q of ["do my products clash", "I have a rash", "hello", "what's the weather"]) {
    const reply = planTurn(q, input).finish([]);
    assert(reply.text.length > 0);
    assert(reply.chips.length >= 1 && reply.chips.length <= MAX_CHIPS);
    assert(!reply.tools_used.includes("model"));
  }
  assertEquals(planTurn("what's the weather", input).finish([]).text, OPEN_WITHOUT_MODEL);
  assert(planTurn("I have a rash", input).finish([]).text.includes("dermatologist"));
});
