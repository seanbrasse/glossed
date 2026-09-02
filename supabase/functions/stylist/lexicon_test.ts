// The simulated corpus: how people ask, in their own words, and the intent
// each should land on — written offline from how beauty is talked about on
// the internet (skincare and curl forums, TikTok, reviews), so the app can
// route by matching. Every row must route without a model. A new phrasing
// that misses is a row for lexicon.ts, then a row here.

import { assertEquals } from "jsr:@std/assert@1";
import { detectIntent, type PlanInput } from "./plan.ts";
import type { StylistContext } from "./tools.ts";

const ctx: StylistContext = {
  profile: { skin_type: null, concerns: [], hair_pattern: "3b", domains: [], climate: null },
  shelf: [{
    user_item_id: "11111111-1111-4111-8111-111111111111",
    product_id: "66666666-6666-4666-8666-666666666666",
    product_name: "niacinamide 10% + zinc",
    brand_name: "the ordinary",
    category_slug: "serum",
    category_label: "serums + actives",
    domain: "skincare",
    status: "own",
    rank_position: null,
    ranked_in_category: 0,
  }],
  routines: [],
  collections: [],
  looks: [{
    id: "33333333-3333-4333-8333-333333333333",
    caption: "golden hour, favorites on",
    state: "draft",
    photo_n: 2,
  }],
};
const input: PlanInput = {
  ctx,
  categories: [
    { id: "a", slug: "serum", label: "serums + actives", domain: "skincare" },
    { id: "b", slug: "sunscreen", label: "sun", domain: "skincare" },
    { id: "c", slug: "foundation", label: "foundation", domain: "makeup" },
    { id: "d", slug: "cleanser", label: "cleanser", domain: "skincare" },
    { id: "e", slug: "styler", label: "stylers", domain: "haircare" },
  ],
  hasShadeAnchor: false,
};

type Expect =
  | "medical"
  | "look"
  | "missing"
  | "try_next"
  | "clash"
  | "greeting"
  | "open"
  | "about_item"
  | `routine:${string}:${string}`
  | `compare:${string}`;

const CORPUS: readonly [string, Expect][] = [
  // — the creative ask, and its cousins
  ["how do I make my going out look slay tonight?", "look"],
  ["grwm for a date, what do i put on", "look"],
  ["soft glam for a wedding this weekend", "look"],
  ["what should i wear on my face tonight", "look"],
  ["recreate my golden hour look tonight", "look"],
  ["no makeup makeup look for brunch", "look"],
  ["full beat for the club pls", "look"],
  ["clean girl look with what i have", "look"],
  ["date night makeup from my stash", "look"],
  // — routines, in every register
  ["build me a morning routine from what I own", "routine:am:skincare"],
  ["what order do i put my stuff on in the morning", "routine:am:skincare"],
  ["what goes first, serum or moisturizer", "routine:am:skincare"],
  ["set up my pm skincare", "routine:pm:skincare"],
  ["night routine pls", "routine:pm:skincare"],
  ["before bed lineup", "routine:pm:skincare"],
  ["what's my wash day routine", "routine:wash_day:haircare"],
  ["wash-day steps for 3b curls", "routine:wash_day:haircare"],
  ["curly girl method routine with my products", "routine:wash_day:haircare"],
  ["sunday reset routine", "routine:weekly:skincare"],
  ["skin cycling with what i own", "routine:am:skincare"],
  ["everyday makeup routine from my shelf", "routine:am:makeup"],
  ["how should i layer my skincare at night", "routine:pm:skincare"],
  // — gaps
  ["what am I missing for dryness", "missing"],
  ["whats missing from my shelf", "missing"],
  ["do i need a toner", "missing"],
  ["am i covered for the basics", "missing"],
  ["what else should i add for acne", "missing"],
  ["starter kit for someone starting from scratch", "missing"],
  ["are there holes in my routine", "missing"],
  // — try next
  ["what should I try next", "try_next"],
  ["recommend me a sunscreen", "try_next"],
  ["any recs for a moisturizer", "try_next"],
  ["what's worth the hype rn", "try_next"],
  ["is the viral cleanser worth it", "try_next"],
  ["what are people like me using", "try_next"],
  ["dupe for my foundation", "try_next"],
  ["what should i buy next", "try_next"],
  ["holy grail serum?", "try_next"],
  ["something similar to my curl cream but cheaper", "try_next"],
  ["top rated spf", "try_next"],
  // — compare
  ["compare my two serums", "compare:serum"],
  ["which of my cleansers is better", "compare:cleanser"],
  ["my serums head to head", "compare:serum"],
  ["which one do i like more, foundation wise", "compare:foundation"],
  ["rank my stylers", "compare:styler"],
  ["which sunscreen is my favourite", "compare:sunscreen"],
  // — clashes
  ["can i use niacinamide together with my cleanser", "clash"],
  ["do these pill when layered", "clash"],
  ["is it safe to use with retinol", "clash"],
  ["can i stack vitamin c and niacinamide", "clash"],
  ["too many actives at once?", "clash"],
  // — medical, before anything else
  ["routine for my rash", "medical"],
  ["I was prescribed tretinoin, what order", "medical"],
  ["fungal acne on my forehead, recommend something", "medical"],
  ["my scalp is burning after the curl cream", "medical"],
  ["going out tonight but my eczema flared", "medical"],
  ["is my hair falling out from the styler", "medical"],
  // — about something on the shelf
  ["what does niacinamide do", "about_item"],
  ["tell me about the ordinary niacinamide", "about_item"],
  // — greetings and small talk
  ["hi", "greeting"],
  ["hey there", "greeting"],
  ["thanks!", "greeting"],
  ["ok", "greeting"],
  // — genuinely open, the model's
  ["what's the capital of peru", "open"],
  ["how long should i wait between serum and moisturizer", "open"],
  ["is it ok to skip toner if my skin feels fine without it?", "open"],
  ["what's the difference between a serum and an essence", "open"],
  ["why does my foundation oxidize", "open"],
  ["im looking for a cleanser that doesnt strip", "try_next"],
];

function shape(i: ReturnType<typeof detectIntent>): string {
  switch (i.kind) {
    case "routine":
      return `routine:${i.slot}:${i.domain}`;
    case "compare":
      return `compare:${i.category_slug}`;
    default:
      return i.kind;
  }
}

for (const [text, expected] of CORPUS) {
  Deno.test(`corpus · "${text}" → ${expected}`, () => {
    assertEquals(shape(detectIntent(text, input)), expected);
  });
}

Deno.test("the corpus names the look the words named", () => {
  const i = detectIntent("recreate my golden hour look tonight", input);
  assertEquals(i.kind === "look" ? i.look_id : null, "33333333-3333-4333-8333-333333333333");
});
