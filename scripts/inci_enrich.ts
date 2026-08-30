// GLO-170 · Parse inci_raw into inci_parsed + product_attributes.
//
// The catalog pipeline's step 3 (tech/01 §4), specified and never built until
// now: per product, once, cached forever. This is the feeder that gives the
// taste engine (tech/07, affinity_for_user in 0035) its dimensions — before
// this ran, 1 of 3,204 canonical products had any attribute.
//
// DERIVATION IS A DICTIONARY, NOT A MODEL, AND NOT A NETWORK CALL. PRD §15's
// guardrail: attributes derive only from structured fields — the INCI list IS
// the structured field — never from marketing copy, and "empty beats
// fabricated." A curated ingredient dictionary over inci_raw is deterministic,
// offline, and auditable line by line below. The INCI API / OBF enrichment
// (functions, allergen flags) can layer on later; nothing here blocks it.
//
// THE VOCABULARY LIVES HERE, NOT IN seed.sql — deliberately. Catalog data has
// always come from scripts (obf_import, shopify_import); seed.sql carries
// test fixtures. The chips are upserted idempotently on slug, so re-runs and
// pre-existing seed fixtures ('fragrance-free', 'silicone-free') are fine.
// PRD open question #3 says derivable chips are legion and surfacing all of
// them is noise, so the set below is deliberately tight: the §15 table, minus
// what needs feed data we don't have (SPF value, finish/coverage) and minus
// judgment calls (buildup risk) — those want their own pass, not a guess in
// this one.
//
// CONSERVATIVE ON PURPOSE, in both directions:
//   - absence chips ("fragrance-free") need inci_parsed length ≥ 5 — a
//     truncated list ("aqua") must not certify a formula free of anything.
//   - citric acid is NOT an AHA here (it is almost always a pH adjuster) and
//     fatty alcohols (cetyl, stearyl…) do NOT break "alcohol-free" — both are
//     the classic false positives, excluded by construction.
//   - magnesium sulfate (epsom salt) does not break "sulfate-free"; only the
//     surfactant family does.
//
// Idempotent: parsing fills only null inci_parsed (--force re-parses all and
// recomputes attributes); attribute inserts land on the PK and re-runs are
// no-ops. A reformulation fork creates a NEW product row (tech/01 §4), which
// arrives here with inci_parsed null and parses clean.
//
// Usage:
//   deno run --allow-run --allow-env scripts/inci_enrich.ts [--dry-run] [--force]

import { psqlArgs, targetLabel } from "./db.ts";

// Say the destination before writing to it.
console.log(`→ writing to ${targetLabel()}`);

const DRY = Deno.args.includes("--dry-run");
const FORCE = Deno.args.includes("--force");

// slug · label · domain (null = every domain) · rule kind · postgres regex
// over lower(inci_raw). Presence = the ingredient family appears. Absence =
// it does not (and the parsed list clears the length floor).
type Rule = {
  slug: string;
  label: string;
  domain: string | null;
  kind: "presence" | "absence";
  pattern: string;
};

const RULES: Rule[] = [
  // ── the "-free" family (PRD §15 "All") — absence, domain-wide ───────────
  { slug: "fragrance-free", label: "fragrance-free", domain: null, kind: "absence",
    pattern: "(parfum|fragrance|\\maroma\\M|linalool|limonene|citronellol|geraniol|eugenol|coumarin)" },
  { slug: "sulfate-free", label: "sulfate-free", domain: null, kind: "absence",
    pattern: "(lauryl|laureth|coco|cetearyl|myreth|olefin)[- ]?(sulfate|sulfonate)" },
  { slug: "silicone-free", label: "silicone-free", domain: null, kind: "absence",
    pattern: "(methicone|siloxane|silsesquioxane|silanol)" },
  { slug: "alcohol-free", label: "alcohol-free", domain: null, kind: "absence",
    pattern: "(alcohol denat|denatured alcohol|sd alcohol|isopropyl alcohol|\\methanol\\M)" },
  { slug: "paraben-free", label: "paraben-free", domain: null, kind: "absence",
    pattern: "paraben" },
  // ── skincare actives (PRD §15 "Skincare") — presence ────────────────────
  { slug: "retinoid", label: "retinoid", domain: "skincare", kind: "presence",
    pattern: "(retinol|retinal\\M|retinaldehyde|retinyl|retinoate|adapalene|tretinoin)" },
  { slug: "vitamin-c", label: "vitamin c", domain: "skincare", kind: "presence",
    pattern: "(ascorbic acid|ascorbyl|ascorbate)" },
  { slug: "niacinamide", label: "niacinamide", domain: "skincare", kind: "presence",
    pattern: "(niacinamide|nicotinamide)" },
  { slug: "aha", label: "aha", domain: "skincare", kind: "presence",
    pattern: "(glycolic acid|lactic acid|mandelic acid|malic acid|tartaric acid)" },
  { slug: "bha", label: "bha", domain: "skincare", kind: "presence",
    pattern: "(salicylic acid|betaine salicylate)" },
  { slug: "benzoyl-peroxide", label: "benzoyl peroxide", domain: "skincare", kind: "presence",
    pattern: "benzoyl peroxide" },
  { slug: "hyaluronic-acid", label: "hyaluronic acid", domain: "skincare", kind: "presence",
    pattern: "(hyaluronic acid|hyaluronate)" },
  { slug: "ceramides", label: "ceramides", domain: "skincare", kind: "presence",
    pattern: "ceramide" },
  // ── haircare (PRD §15: "no catalog sells hair attributes — we compute") ─
  { slug: "protein", label: "protein", domain: "haircare", kind: "presence",
    pattern: "(hydrolyzed [a-z ]*protein|keratin|collagen)" },
];

const q = (s: string) => `'${s.replaceAll("'", "''")}'`;

async function runSQL(statements: string): Promise<string> {
  const psql = new Deno.Command("docker", {
    args: psqlArgs(["-q", "-v", "ON_ERROR_STOP=1"]),
    stdin: "piped", stdout: "piped", stderr: "piped",
  }).spawn();
  const writer = psql.stdin.getWriter();
  await writer.write(new TextEncoder().encode(statements));
  await writer.close();
  const out = await psql.output();
  if (!out.success) throw new Error(new TextDecoder().decode(out.stderr));
  return new TextDecoder().decode(out.stdout);
}

// 1 · vocabulary — idempotent on slug, so seed fixtures keep their ids
const vocab = RULES.map((r) =>
  `insert into attribute_chips (domain, slug, label)
   values (${r.domain ? `'${r.domain}'` : "null"}, ${q(r.slug)}, ${q(r.label)})
   on conflict (slug) do nothing;`
).join("\n");

// 2 · parse inci_raw → inci_parsed. Split on commas NOT followed by a digit,
// so "1,2-hexanediol" stays one ingredient. Lowercased, trimmed, de-blanked.
const parse = `
update products set inci_parsed = (
    select jsonb_agg(t) from (
        select nullif(trim(x), '') as t
        from unnest(regexp_split_to_array(lower(inci_raw), ',\\s*(?![0-9])')) x
    ) s where t is not null
)
where inci_raw is not null ${FORCE ? "" : "and inci_parsed is null"};`;

// 3 · derive. Presence: regex hits lower(inci_raw). Absence: it does not,
// and the parsed list has ≥ 5 entries (a stub list certifies nothing).
const derive = RULES.map((r) => {
  const cond = r.kind === "presence"
    ? `lower(p.inci_raw) ~ ${q(r.pattern)}`
    : `lower(p.inci_raw) !~ ${q(r.pattern)} and jsonb_array_length(p.inci_parsed) >= 5`;
  const domainGuard = r.domain ? `and p.domain = '${r.domain}'` : "";
  return `
insert into product_attributes (product_id, attribute_chip_id, source)
select p.id, ac.id, 'inci'
from products p, attribute_chips ac
where ac.slug = ${q(r.slug)}
  and p.inci_raw is not null and p.inci_parsed is not null
  ${domainGuard}
  and ${cond}
on conflict do nothing;`;
}).join("\n");

const report = `
select 'parsed' as what, count(*)::text as n from products where inci_parsed is not null
union all
select 'products with >=1 attribute', count(distinct product_id)::text from product_attributes
union all
select 'attr · ' || ac.slug, count(pa.product_id)::text
from attribute_chips ac left join product_attributes pa on pa.attribute_chip_id = ac.id
group by ac.slug
order by 1;`;

if (DRY) {
  console.log("-- dry run: vocabulary + parse + derivation SQL follows, not executed --");
  console.log(vocab, parse, derive);
} else {
  if (FORCE) {
    await runSQL(`delete from product_attributes where source = 'inci';`);
    console.log("force: cleared source='inci' attributes for recompute");
  }
  await runSQL(vocab);
  await runSQL(parse);
  await runSQL(derive);
}
console.log(await runSQL(report));
