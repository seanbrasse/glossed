// The Stylist's rules half (docs/tech/08-stylist.md, Sean Sept 2: "as little
// AI as possible — searching, filtering, looking at data and making
// comparisons"). A turn is planned here from the person's own context and
// the words they used; the shaped answers — a routine from the shelf, the
// gaps a concern wants filled, what to try next, a comparison of what they
// own — are built from data and templates, never generated. The model is
// reached only for a free-form question no rule covers (index.ts decides).
//
// Pure: no I/O. A plan names the fetches it wants (leaderboard, discover,
// crosswalk) and finishes from their rows. Tested by plan_test.ts.

import {
  type Block,
  type CatalogHit,
  MAX_CHIPS,
  MAX_PRODUCTS_SHOWN,
  MAX_ROUTINE_STEPS,
  type Reply,
  type ShelfItem,
  type Slot,
  SLOTS,
  type StylistContext,
} from "./tools.ts";
import {
  CATEGORY_WORDS,
  CLASH_WORDS,
  COMPARE_WORDS,
  DOMAIN_WORDS,
  GREETING_WORDS,
  hasAny,
  hasWord,
  longestMatch,
  LOOK_WORDS,
  MEDICAL_WORDS,
  MISSING_WORDS,
  OCCASION_WORDS,
  ROUTINE_WORDS,
  SLOT_WORDS,
  TRY_NEXT_WORDS,
} from "./lexicon.ts";

export type Domain = "skincare" | "makeup" | "haircare" | "fragrance";
export const DOMAINS: readonly Domain[] = ["skincare", "makeup", "haircare", "fragrance"];

export type Intent =
  | { readonly kind: "routine"; readonly slot: Slot; readonly domain: Domain }
  /// A look for an occasion — makeup from the shelf, in order, and the
  /// person's own saved looks as doors; `look_id` when the words named one.
  | { readonly kind: "look"; readonly look_id: string | null }
  | { readonly kind: "missing" }
  | { readonly kind: "try_next" }
  | { readonly kind: "compare"; readonly category_slug: string | null }
  | { readonly kind: "about_item"; readonly user_item_id: string }
  | { readonly kind: "clash" }
  | { readonly kind: "medical" }
  | { readonly kind: "greeting" }
  /// Nothing above matched: a free-form beauty question, the model's if a
  /// key exists, otherwise the honest menu.
  | { readonly kind: "open" };

/// One category the caller may rank in — `categories` where parent_id is
/// null, prefetched so a slug from the shelf can become a leaderboard call.
export interface CategoryRef {
  readonly id: string;
  readonly slug: string;
  readonly label: string;
  readonly domain: Domain;
}

export type Fetch =
  | {
    readonly kind: "leaderboard";
    readonly category: CategoryRef;
    readonly scope: "all" | "yours";
    readonly limit: number;
  }
  | { readonly kind: "discover"; readonly limit: number }
  | { readonly kind: "crosswalk"; readonly limit: number };

/// A row back from one of the cohort reads, on top of the catalog shape.
export interface DataRow extends CatalogHit {
  readonly n_users?: number | null;
  readonly mean_percentile?: number | null;
  readonly basis?: string | null;
  readonly basis_n?: number | null;
  readonly anchor_label?: string | null;
  readonly n?: number | null;
}

export interface FetchResult {
  readonly fetch: Fetch;
  readonly rows: readonly DataRow[];
}

export interface Planned {
  readonly intent: Intent;
  readonly fetches: readonly Fetch[];
  readonly finish: (results: readonly FetchResult[]) => Reply;
}

/// What the planner knows beyond the context: the rankable categories and
/// whether the person has a shade anchor (the makeup cohort key).
export interface PlanInput {
  readonly ctx: StylistContext;
  readonly categories: readonly CategoryRef[];
  readonly hasShadeAnchor: boolean;
}

// ── vocabulary ─────────────────────────────────────────────────────────────

/// Step order per slot and domain, by category slug. A routine is what you
/// own, in the order it goes on; a slug the shelf has nothing in is skipped,
/// and the first ESSENTIAL missing is named as the one gap.
const ORDER: Record<Domain, Partial<Record<Slot, readonly string[]>>> = {
  skincare: {
    am: ["cleanser", "toner", "serum", "eye", "moisturizer", "sunscreen"],
    pm: ["cleanser", "exfoliant", "toner", "serum", "treatment", "eye", "moisturizer", "lipcare"],
    weekly: ["exfoliant", "mask", "treatment"],
  },
  haircare: {
    wash_day: ["shampoo", "scalp", "conditioner", "styler"],
    am: ["styler"],
    pm: ["scalp"],
  },
  makeup: {
    am: [
      "primer",
      "foundation",
      "concealer",
      "bronzer",
      "blush",
      "highlighter",
      "brow",
      "eyeshadow",
      "eyeliner",
      "mascara",
      "lip",
      "setting",
    ],
  },
  fragrance: { am: ["fragrance"], pm: ["fragrance"] },
};

const ESSENTIAL: Record<Domain, Partial<Record<Slot, readonly string[]>>> = {
  skincare: { am: ["cleanser", "moisturizer", "sunscreen"], pm: ["cleanser", "moisturizer"] },
  haircare: { wash_day: ["shampoo", "conditioner"] },
  makeup: {},
  fragrance: {},
};

const GAP_REASON: Record<string, string> = {
  sunscreen: "the step that protects everything above it",
  moisturizer: "seals the rest in",
  cleanser: "where every routine starts",
  shampoo: "wash day starts here",
  conditioner: "slip after the shampoo",
  exfoliant: "once a week, and only once",
};

const STEP_NOTE: Partial<Record<Slot, Record<string, string>>> = {
  am: { sunscreen: "last, every morning" },
  pm: { exfoliant: "not every night" },
};

/// The tune screen's concern vocabulary (TuneModel.concernOptions) → the
/// categories that concern usually wants on the shelf. The basics apply
/// when no concern is stated.
const CONCERN_WANTS: Record<string, readonly string[]> = {
  dryness: ["moisturizer", "serum", "sunscreen"],
  acne: ["cleanser", "treatment", "sunscreen"],
  texture: ["exfoliant", "serum", "sunscreen"],
  redness: ["cleanser", "moisturizer", "sunscreen"],
  "dark spots": ["sunscreen", "serum", "treatment"],
  "fine lines": ["serum", "moisturizer", "sunscreen", "eye"],
};
const BASICS = ["cleanser", "moisturizer", "sunscreen"] as const;

const SLOT_WORD: Record<Slot, string> = {
  am: "morning",
  pm: "night",
  weekly: "weekly",
  wash_day: "wash day",
};

// ── intent ─────────────────────────────────────────────────────────────────

/// The words pick the intent, from `lexicon.ts` — learned offline, matched
/// at zero tokens. Medical first (it wins over any other word), then the
/// creative asks (a look for tonight), then the shaped ones; a shelf item
/// named in the message answers as itself; everything else is `open`.
export function detectIntent(text: string, input: PlanInput): Intent {
  const t = text.toLowerCase().trim();
  if (hasAny(t, MEDICAL_WORDS)) return { kind: "medical" };
  const occasion = hasAny(t, OCCASION_WORDS);
  if (hasAny(t, LOOK_WORDS) || (occasion && (domainOf(t) === "makeup" || hasWord(t, "look")))) {
    return { kind: "look", look_id: detectLook(t, input.ctx.looks) };
  }
  if (hasAny(t, MISSING_WORDS)) return { kind: "missing" };
  if (hasAny(t, ROUTINE_WORDS)) return { kind: "routine", ...routineShape(t, input.ctx) };
  if (hasAny(t, COMPARE_WORDS)) {
    return { kind: "compare", category_slug: detectCategory(t, input.categories) };
  }
  if (hasAny(t, TRY_NEXT_WORDS)) return { kind: "try_next" };
  if (hasAny(t, CLASH_WORDS)) return { kind: "clash" };
  const item = detectShelfItem(t, input.ctx.shelf);
  if (item) return { kind: "about_item", user_item_id: item.user_item_id };
  if (
    t.length < 4 ||
    GREETING_WORDS.some((g) =>
      t === g || t.startsWith(`${g} `) || t.startsWith(`${g},`) || t.startsWith(`${g}!`)
    )
  ) {
    return { kind: "greeting" };
  }
  return { kind: "open" };
}

/// The model's plan tools name the same intents — the words are the
/// model's, the answer is the rules'. Null when the input is not a shape.
export function intentFromTool(
  name: string,
  input: Record<string, unknown>,
  planInput: PlanInput,
): Intent | null {
  switch (name) {
    case "build_routine": {
      const slot =
        typeof input.slot === "string" && (SLOTS as readonly string[]).includes(input.slot)
          ? input.slot as Slot
          : null;
      const domain =
        typeof input.domain === "string" && (DOMAINS as readonly string[]).includes(input.domain)
          ? input.domain as Domain
          : null;
      return slot && domain ? { kind: "routine", slot, domain } : null;
    }
    case "find_gaps":
      return { kind: "missing" };
    case "what_to_try":
      return { kind: "try_next" };
    case "compare_owned": {
      const slug = typeof input.category_slug === "string" &&
          planInput.categories.some((c) => c.slug === input.category_slug)
        ? input.category_slug
        : null;
      return { kind: "compare", category_slug: slug };
    }
    case "look_for_tonight":
      return { kind: "look", look_id: null };
    default:
      return null;
  }
}

function domainOf(t: string): Domain | null {
  let best: { domain: Domain; length: number } | null = null;
  for (const domain of DOMAINS) {
    const m = longestMatch(t, DOMAIN_WORDS[domain]);
    if (m && (best === null || m.length > best.length)) best = { domain, length: m.length };
  }
  return best?.domain ?? null;
}

function routineShape(t: string, ctx: StylistContext): { slot: Slot; domain: Domain } {
  let slot: Slot = defaultSlot(ctx);
  let length = 0;
  for (const s of SLOTS) {
    const m = longestMatch(t, SLOT_WORDS[s]);
    if (m && m.length > length) {
      slot = s;
      length = m.length;
    }
  }
  const domain = slot === "wash_day" ? "haircare" : domainOf(t) ?? "skincare";
  return { slot, domain };
}

export function detectCategory(t: string, categories: readonly CategoryRef[]): string | null {
  let best: { slug: string; length: number } | null = null;
  for (const c of categories) {
    const m = longestMatch(t, [c.slug, c.label, ...(CATEGORY_WORDS[c.slug] ?? [])]);
    if (m && m.length >= 3 && (best === null || m.length > best.length)) {
      best = { slug: c.slug, length: m.length };
    }
  }
  return best?.slug ?? null;
}

/// The shelf item the words name, if one — the longest run of its own
/// name's words (four letters or more) found in the message.
export function detectShelfItem(t: string, shelf: readonly ShelfItem[]): ShelfItem | null {
  let best: { item: ShelfItem; score: number } | null = null;
  for (const item of shelf) {
    const words = item.product_name.toLowerCase().split(/[^a-z0-9%+']+/).filter((w) =>
      w.length >= 4
    );
    const brand = item.brand_name.toLowerCase();
    let score = words.filter((w) => hasWord(t, w)).length;
    if (score > 0 && brand.length >= 3 && t.includes(brand)) score += 1;
    if (score > 0 && (best === null || score > best.score)) best = { item, score };
  }
  return best?.item ?? null;
}

/// One of the person's own looks, when its caption's words are in the
/// message ("recreate my golden hour look").
export function detectLook(t: string, looks: StylistContext["looks"]): string | null {
  let best: { id: string; score: number } | null = null;
  for (const look of looks) {
    const words = (look.caption ?? "").toLowerCase().split(/[^a-z0-9']+/).filter((w) =>
      w.length >= 4
    );
    const score = words.filter((w) => hasWord(t, w)).length;
    if (score > 0 && (best === null || score > best.score)) best = { id: look.id, score };
  }
  return best?.id ?? null;
}

// ── the plan ───────────────────────────────────────────────────────────────

export function planTurn(text: string, input: PlanInput): Planned {
  return planIntent(detectIntent(text, input), input);
}

export function planIntent(intent: Intent, input: PlanInput): Planned {
  switch (intent.kind) {
    case "routine":
      return done(intent, buildRoutineReply(intent.slot, intent.domain, input.ctx));
    case "look":
      return done(intent, lookReply(intent.look_id, input.ctx));
    case "missing":
      return planMissing(intent, input);
    case "try_next":
      return {
        intent,
        fetches: [{ kind: "discover", limit: 8 }, { kind: "crosswalk", limit: 6 }],
        finish: (results) => finishTryNext(input.ctx, results),
      };
    case "compare":
      return done(intent, compareReply(intent.category_slug, input));
    case "about_item":
      return done(intent, aboutItemReply(intent.user_item_id, input.ctx));
    case "clash":
      return done(
        intent,
        reply(
          "i don't have ingredient lists yet, so i won't guess at clashes. " +
            "when i do, this is the first thing i'll check.",
          [],
          chipsFor(input.ctx, ["build my am routine", "compare what i own"]),
          ["shelf"],
          ["plan_clash"],
        ),
      );
    case "medical":
      return done(
        intent,
        reply(
          "that sounds like one for a dermatologist — i stay on the beauty half. " +
            "when you're ready, i can build a routine from what you own.",
          [],
          chipsFor(input.ctx, ["build my am routine", "what should i try next"]),
          [],
          ["plan_medical"],
        ),
      );
    case "greeting":
      return done(intent, menuReply(input.ctx, "hi. i know your shelf — ask me for one of these."));
    case "open":
      return done(intent, menuReply(input.ctx, OPEN_WITHOUT_MODEL));
  }
}

export const OPEN_WITHOUT_MODEL =
  "i can build a routine from what you own, find the gaps, compare your products, " +
  "or say what to try next — ask one of those.";

function done(intent: Intent, r: Reply): Planned {
  return { intent, fetches: [], finish: () => r };
}

function reply(
  text: string,
  blocks: readonly Block[],
  chips: readonly string[],
  groundedIn: readonly string[],
  toolsUsed: readonly string[],
): Reply {
  return {
    text,
    blocks,
    chips: chips.slice(0, MAX_CHIPS),
    grounded_in: groundedIn,
    tools_used: toolsUsed,
  };
}

/// The slot a routine ask lands on when the words name none: the first the
/// person does not keep yet (morning, then night, then weekly), so "build
/// me a routine" is never the one they already have.
export function defaultSlot(ctx: StylistContext, domain: Domain = "skincare"): Slot {
  const kept = new Set(ctx.routines.map((r) => r.slot));
  const open = (["am", "pm", "weekly"] as const).filter((s) => !kept.has(s));
  // A slot the shelf can actually fill comes first: a weekly needs an
  // exfoliant, a mask or a treatment, and most shelves have none.
  return open.find((s) => buildRoutine(s, domain, ctx) !== null) ?? open[0] ?? "am";
}

/// Chips the person can actually use (Sean, Sept 2: "what if I already
/// built a pm routine? chips need to be less specific or smarter"): a
/// routine chip names a slot they do not keep yet, or gives way when they
/// keep them all; a comparison needs two things on the shelf; nothing is
/// offered twice.
export function chipsFor(ctx: StylistContext, preferred: readonly string[]): string[] {
  const kept = new Set(ctx.routines.map((r) => r.slot));
  const open = (["am", "pm", "weekly"] as const).filter((s) => !kept.has(s));
  const out: string[] = [];
  for (const chip of preferred) {
    let c: string | null = chip;
    const m = /^build my (am|pm|weekly|night skincare) routine$/.exec(chip);
    if (m) {
      const asked = m[1] === "night skincare" ? "pm" : m[1];
      const slot = kept.has(asked) ? open[0] ?? null : asked;
      c = slot ? `build my ${slot} routine` : "a look for tonight";
    }
    if (c === "compare what i own" && ctx.shelf.length < 2) c = null;
    if (c && !out.includes(c)) out.push(c);
  }
  for (
    const extra of ["what's missing for my skin", "what should i try next", "a look for tonight"]
  ) {
    if (out.length >= MAX_CHIPS) break;
    if (!out.includes(extra)) out.push(extra);
  }
  return out.slice(0, MAX_CHIPS);
}

function menuReply(ctx: StylistContext, text: string): Reply {
  return reply(
    text,
    [],
    chipsFor(ctx, ["build my am routine", "what's missing for my skin", "what should i try next"]),
    ["shelf"],
    ["plan_menu"],
  );
}

// ── routine ────────────────────────────────────────────────────────────────

type RoutineBlock = Extract<Block, { type: "routine_draft" }>;

/// Picks one owned item per category in the slot's order: owned before
/// wanted, the person's own rank first, then the name so a tie is stable.
export function buildRoutine(
  slot: Slot,
  domain: Domain,
  ctx: StylistContext,
): RoutineBlock | null {
  const order = ORDER[domain][slot] ?? ORDER[domain].am ?? [];
  const steps: RoutineBlock["steps"][number][] = [];
  for (const slug of order) {
    const pick = bestOwned(ctx.shelf, slug);
    if (!pick) continue;
    steps.push({
      user_item_id: pick.user_item_id,
      product_name: pick.product_name,
      brand_name: pick.brand_name,
      category_label: pick.category_label,
      note: STEP_NOTE[slot]?.[slug] ?? null,
    });
    if (steps.length === MAX_ROUTINE_STEPS) break;
  }
  if (steps.length === 0) return null;
  const owned = new Set(ctx.shelf.map((s) => s.category_slug));
  const missing = (ESSENTIAL[domain][slot] ?? []).find((slug) => !owned.has(slug)) ?? null;
  const gap = missing
    ? {
      category_label: ctx.shelf.find((s) => s.category_slug === missing)?.category_label ??
        missing,
      reason: GAP_REASON[missing] ?? "the step your shelf has nothing for",
    }
    : null;
  return {
    type: "routine_draft",
    title: `${SLOT_WORD[slot]} ${domain === "haircare" ? "hair" : domain}`,
    slot,
    targets: ctx.profile.concerns.slice(0, 4),
    steps,
    gap,
  };
}

function bestOwned(shelf: readonly ShelfItem[], slug: string): ShelfItem | null {
  const candidates = shelf.filter((s) => s.category_slug === slug && s.status !== "want_to_try");
  candidates.sort((a, b) => {
    const ra = a.rank_position ?? Number.MAX_SAFE_INTEGER;
    const rb = b.rank_position ?? Number.MAX_SAFE_INTEGER;
    return ra - rb || a.product_name.localeCompare(b.product_name);
  });
  return candidates[0] ?? null;
}

function buildRoutineReply(slot: Slot, domain: Domain, ctx: StylistContext): Reply {
  const block = buildRoutine(slot, domain, ctx);
  const word = SLOT_WORD[slot];
  const domainWord = domain === "haircare" ? "hair" : domain;
  if (!block) {
    const wants = (ORDER[domain][slot] ?? ORDER[domain].am ?? []).map((slug) =>
      ctx.shelf.find((s) => s.category_slug === slug)?.category_label ?? slug
    );
    const owned = ctx.shelf.some((s) => s.domain === domain);
    return reply(
      owned
        ? `nothing on your shelf fits a ${word} ${domainWord} — that's ${
          joinWords(wants.slice(0, 3))
        }. log one and i'll build it.`
        : `nothing ${domainWord} on your shelf yet, so there's no ${word} to build. ` +
          "log a product and i'll start from it.",
      [],
      chipsFor(ctx, ["what should i try next", "what's missing for my skin"]),
      ["shelf"],
      ["plan_routine"],
    );
  }
  const n = block.steps.length;
  const existing = ctx.routines.find((r) => r.slot === slot);
  const lines = [
    `your ${word} ${domainWord}, from what you own — ${n} ${n === 1 ? "step" : "steps"}.`,
  ];
  if (block.gap) lines.push(`the one gap is ${block.gap.category_label}.`);
  else if ((ESSENTIAL[domain][slot] ?? []).length > 0) {
    lines.push("nothing missing from the basics.");
  }
  if (existing) {
    lines.push(
      `you already keep "${existing.title}" for the ${word}; this one would sit beside it.`,
    );
  }
  if (ctx.profile.concerns.length === 0 && domain === "skincare") {
    lines.push("add your concerns in tune and i'll aim it.");
  }
  const next = slot === "am"
    ? ["build my pm routine", "what's missing for my skin", "what should i try next"]
    : ["build my am routine", "what's missing for my skin", "what should i try next"];
  return reply(lines.join(" "), [block], chipsFor(ctx, next), ["profile", "shelf", "routines"], [
    "plan_routine",
  ]);
}

// ── look ───────────────────────────────────────────────────────────────────

/// A look for tonight: makeup from the shelf in the order it goes on, and
/// the person's own saved looks as doors (the named one first). Nothing is
/// invented — no product they do not own, no look they did not save.
export function lookReply(lookID: string | null, ctx: StylistContext): Reply {
  const routine = buildRoutine("pm", "makeup", ctx);
  const named = lookID ? ctx.looks.find((l) => l.id === lookID) ?? null : null;
  const looks = [
    ...(named ? [named] : []),
    ...ctx.looks.filter((l) => l.id !== named?.id),
  ].slice(0, 2);
  const blocks: Block[] = [];
  if (routine) blocks.push({ ...routine, title: "tonight, from your shelf" });
  for (const l of looks) {
    blocks.push({ type: "look_ref", look_id: l.id, caption: l.caption, photo_n: l.photo_n });
  }
  const lines: string[] = [];
  if (routine) {
    const n = routine.steps.length;
    lines.push(
      `for tonight, from what you own — ${n} makeup ${n === 1 ? "step" : "steps"}, in order.`,
    );
  } else lines.push("nothing makeup logged on your shelf yet, so there's no order to give.");
  if (named) {
    lines.push(`your "${named.caption}" look is below — open it and its products are the recipe.`);
  } else if (looks.length > 0) {
    lines.push("your saved looks are below — open one and its products are the recipe.");
  }
  if (!routine && looks.length === 0) lines.push("log what you'd wear and i'll order it.");
  return reply(
    lines.join(" "),
    blocks,
    chipsFor(ctx, ["build my night skincare", "what should i try next", "compare my lip"]),
    ["shelf", "looks"],
    ["plan_look"],
  );
}

// ── missing ────────────────────────────────────────────────────────────────

/// The set difference: what the stated concerns usually want, less what the
/// shelf holds — then the leaderboard for each gap, the person's cohort
/// first where one resolves (haircare by hair pattern, makeup by shade
/// anchor), everyone otherwise. `leaderboard()` falls back to 'all'
/// silently for skincare, so the label is decided HERE, from what we know.
export function missingCategories(ctx: StylistContext): string[] {
  const wanted = new Set<string>();
  const concerns = ctx.profile.concerns.filter((c) => CONCERN_WANTS[c]);
  for (const c of concerns.length > 0 ? concerns : []) {
    for (const slug of CONCERN_WANTS[c]) wanted.add(slug);
  }
  if (wanted.size === 0) { for (const slug of BASICS) wanted.add(slug); }
  const owned = new Set(ctx.shelf.map((s) => s.category_slug));
  return [...wanted].filter((slug) => !owned.has(slug));
}

function planMissing(intent: Intent, input: PlanInput): Planned {
  const { ctx } = input;
  const missing = missingCategories(ctx).slice(0, 3);
  const concernWord = ctx.profile.concerns.length > 0
    ? ctx.profile.concerns.join(", ")
    : "the basics";
  if (missing.length === 0) {
    return done(
      intent,
      reply(
        `for ${concernWord}, your shelf already covers every category that usually helps.`,
        [],
        chipsFor(ctx, ["build my am routine", "what should i try next"]),
        ["profile", "shelf"],
        ["plan_missing"],
      ),
    );
  }
  const fetches: Fetch[] = [];
  for (const slug of missing) {
    const category = input.categories.find((c) => c.slug === slug);
    if (!category) continue;
    fetches.push({ kind: "leaderboard", category, scope: cohortScope(category, input), limit: 2 });
  }
  return {
    intent,
    fetches,
    finish: (results) => {
      const products: ProductRow[] = [];
      const empty: string[] = [];
      for (const r of results) {
        if (r.fetch.kind !== "leaderboard") continue;
        if (r.rows.length === 0) {
          empty.push(r.fetch.category.label);
          continue;
        }
        const label = cohortLabel(r.fetch.category, r.fetch.scope, ctx);
        for (const row of r.rows) {
          products.push(productRow(row, ctx, label, row.n_face_offs ?? 0));
        }
      }
      const labels = missing.map((slug) =>
        input.categories.find((c) => c.slug === slug)?.label ?? slug
      );
      const lines = [`for ${concernWord}, your shelf has no ${joinWords(labels)}.`];
      if (products.length > 0) lines.push("here's what people rank highest in each, with the n.");
      if (empty.length > 0) lines.push(`no receipts yet for ${joinWords(empty)}.`);
      const blocks: Block[] = products.length > 0
        ? [{
          type: "product_list",
          reason: `the ${labels.length === 1 ? "category" : "categories"} your shelf is missing`,
          products: products.slice(0, MAX_PRODUCTS_SHOWN),
        }]
        : [];
      return reply(
        lines.join(" "),
        blocks,
        chipsFor(ctx, ["build my am routine", "what should i try next"]),
        ["profile", "shelf", ...(fetches.length > 0 ? ["leaderboard"] : [])],
        ["plan_missing", ...(fetches.length > 0 ? ["leaderboard"] : [])],
      );
    },
  };
}

export function cohortScope(category: CategoryRef, input: PlanInput): "all" | "yours" {
  if (category.domain === "haircare" && input.ctx.profile.hair_pattern) return "yours";
  if (category.domain === "makeup" && input.hasShadeAnchor) return "yours";
  return "all";
}

function cohortLabel(category: CategoryRef, scope: "all" | "yours", ctx: StylistContext): string {
  if (scope === "yours" && category.domain === "haircare") {
    return `face-offs by people with ${ctx.profile.hair_pattern} hair`;
  }
  if (scope === "yours" && category.domain === "makeup") {
    return "face-offs by people who wear your shade";
  }
  return `face-offs in ${category.label}, everyone`;
}

// ── try next ───────────────────────────────────────────────────────────────

const BASIS_LABEL: Record<string, string> = {
  taste: "of your own signals lean this way",
  shade: "face-offs by people who wear your shade",
  everyone: "face-offs, everyone",
  popular: "people own it",
  exploration: "a wander, no evidence",
};

function finishTryNext(ctx: StylistContext, results: readonly FetchResult[]): Reply {
  const products: ProductRow[] = [];
  const seen = new Set<string>();
  const discover = results.find((r) => r.fetch.kind === "discover")?.rows ?? [];
  const crosswalk = results.find((r) => r.fetch.kind === "crosswalk")?.rows ?? [];
  for (const row of crosswalk) {
    if (seen.has(row.id)) continue;
    seen.add(row.id);
    products.push(
      productRow(
        row,
        ctx,
        `people who wear ${row.anchor_label ?? "your shade"} also wear it`,
        row.n ?? 0,
      ),
    );
  }
  for (const row of discover) {
    if (seen.has(row.id)) continue;
    seen.add(row.id);
    const basis = row.basis ?? "everyone";
    products.push(
      productRow(row, ctx, BASIS_LABEL[basis] ?? BASIS_LABEL.everyone, row.basis_n ?? 0),
    );
  }
  const withReceipts = products.filter((p) => (p.basis_n ?? 0) > 0).length;
  const shown = products.slice(0, MAX_PRODUCTS_SHOWN);
  if (shown.length === 0) {
    return reply(
      "nothing with receipts yet — rank a few face-offs and this fills in from people like you.",
      [],
      chipsFor(ctx, ["build my am routine", "what's missing for my skin"]),
      ["shelf"],
      ["plan_try_next", "discover", "crosswalk"],
    );
  }
  const lines = [
    `from your logs and people like you — ${withReceipts} with receipts` +
    (shown.length > withReceipts ? `, ${shown.length - withReceipts} without.` : "."),
  ];
  if (ctx.shelf.every((s) => s.rank_position === null)) {
    lines.push("rank what you own and the receipts get sharper.");
  }
  return reply(
    lines.join(" "),
    [{ type: "product_list", reason: "what to try next, each with its n", products: shown }],
    chipsFor(ctx, ["what's missing for my skin", "build my am routine", "compare what i own"]),
    ["shelf", "discover", "crosswalk"],
    ["plan_try_next", "discover", "crosswalk"],
  );
}

// ── compare / about ────────────────────────────────────────────────────────

function compareReply(slug: string | null, input: PlanInput): Reply {
  const { ctx } = input;
  const bySlug = (s: string) => ctx.shelf.filter((i) => i.category_slug === s);
  let items: ShelfItem[] = slug ? bySlug(slug) : [];
  let label = slug ? input.categories.find((c) => c.slug === slug)?.label ?? slug : null;
  if (!slug) {
    // No category named: the one they own the most of, if it has two.
    const counts = new Map<string, number>();
    for (const s of ctx.shelf) counts.set(s.category_slug, (counts.get(s.category_slug) ?? 0) + 1);
    const top = [...counts.entries()].sort((a, b) => b[1] - a[1])[0];
    if (top && top[1] > 1) {
      items = bySlug(top[0]);
      label = items[0].category_label;
    }
  }
  if (!label) {
    return reply(
      "name the category and i'll compare what you own in it — say serums, or foundation.",
      [],
      chipsFor(ctx, ["build my am routine", "what should i try next"]),
      ["shelf"],
      ["plan_compare"],
    );
  }
  if (items.length === 0) {
    return reply(
      `no ${label} on your shelf yet.`,
      [],
      chipsFor(ctx, ["what should i try next", "what's missing for my skin"]),
      ["shelf"],
      ["plan_compare"],
    );
  }
  if (items.length === 1) {
    const one = items[0];
    return reply(
      `one ${label} on your shelf — ${one.product_name} by ${one.brand_name}. ` +
        "log another and rank the two, and i'll compare them.",
      [{ type: "product_list", reason: `your ${label}`, products: [shelfRow(one)] }],
      chipsFor(ctx, ["what should i try next", "build my am routine"]),
      ["shelf"],
      ["plan_compare"],
    );
  }
  const ranked = [...items].sort((a, b) =>
    (a.rank_position ?? Number.MAX_SAFE_INTEGER) - (b.rank_position ?? Number.MAX_SAFE_INTEGER)
  );
  const first = ranked[0];
  const text = first.rank_position !== null
    ? `you ranked ${first.product_name} #${first.rank_position} of ${first.ranked_in_category} in ${label}` +
      (ranked[1].rank_position !== null
        ? `; ${ranked[1].product_name} sits #${ranked[1].rank_position}.`
        : ".")
    : `you own ${items.length} ${label} and haven't ranked them yet — a face-off would settle it.`;
  return reply(
    text,
    [{
      type: "product_list",
      reason: `your ${label}, in your order`,
      products: ranked.map(shelfRow),
    }],
    chipsFor(ctx, ["what should i try next", "build my am routine"]),
    ["shelf"],
    ["plan_compare"],
  );
}

function aboutItemReply(userItemID: string, ctx: StylistContext): Reply {
  const item = ctx.shelf.find((s) => s.user_item_id === userItemID);
  if (!item) return menuReply(ctx, OPEN_WITHOUT_MODEL);
  const lines = [`${item.product_name} by ${item.brand_name} — ${item.category_label}.`];
  if (item.benefit_line) lines.push(`the catalog says: ${item.benefit_line}.`);
  if (item.rank_position !== null && item.ranked_in_category > 0) {
    lines.push(`you ranked it #${item.rank_position} of ${item.ranked_in_category}.`);
  } else lines.push("you haven't ranked it yet.");
  const inRoutines = ctx.routines.filter((r) =>
    r.steps.some((s) => s.user_item_id === item.user_item_id)
  );
  if (inRoutines.length > 0) {
    lines.push(`it's in ${joinWords(inRoutines.map((r) => `"${r.title}"`), "and")}.`);
  }
  return reply(
    lines.join(" "),
    [{ type: "product_list", reason: "on your shelf", products: [shelfRow(item)] }],
    chipsFor(ctx, [`compare my ${item.category_label}`.slice(0, 32), "build my am routine"]),
    ["shelf", "routines"],
    ["plan_about_item"],
  );
}

// ── rows ───────────────────────────────────────────────────────────────────

type ProductRow = Extract<Block, { type: "product_list" }>["products"][number];

function shelfRow(item: ShelfItem): ProductRow {
  return {
    product_id: item.product_id,
    name: item.product_name,
    brand_name: item.brand_name,
    category_slug: item.category_slug,
    on_shelf: true,
    rank_position: item.rank_position,
    ranked_in_category: item.ranked_in_category,
    n_face_offs: null,
    catalog_image_key: item.catalog_image_key ?? null,
    basis_label: null,
    basis_n: null,
  };
}

function productRow(
  row: DataRow,
  ctx: StylistContext,
  basisLabel: string,
  basisN: number,
): ProductRow {
  const shelf = ctx.shelf.find((s) => s.product_id === row.id);
  return {
    product_id: row.id,
    name: row.name,
    brand_name: row.brand_name,
    category_slug: row.category_slug,
    on_shelf: shelf !== undefined,
    rank_position: shelf?.rank_position ?? null,
    ranked_in_category: shelf?.ranked_in_category ?? null,
    n_face_offs: row.n_face_offs ?? null,
    catalog_image_key: row.catalog_image_key ?? null,
    basis_label: basisLabel,
    basis_n: basisN,
  };
}

function joinWords(words: readonly string[], conjunction = "or"): string {
  if (words.length <= 1) return words[0] ?? "";
  return `${words.slice(0, -1).join(", ")} ${conjunction} ${words[words.length - 1]}`;
}
