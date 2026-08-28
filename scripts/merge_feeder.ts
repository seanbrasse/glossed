// GLO-85 · Feed the merge queue: same-brand near-duplicate candidate pairs.
//
// The catalog's gates make exact duplicates impossible (brand + normalize_name
// on every import, GTINs unique) and the shade collapse handled the one
// mechanical pattern. What remains is the middle band: same brand, names close
// enough that they *might* be the same product — minis vs full size, refills,
// travel sizes, "- Box" vs "- Bag". Those are adjudication calls, so this pass
// only queues them into merge_candidates (state 'pending'); it can never merge.
//
// Never auto-merge, at any similarity. The live catalog proves the top of the
// band lies: "…Serum With Essential Oil" vs "…Without Essential Oil" score
// 0.92 and are different products, and fenty's liquid-vs-powder foundations
// cluster at 0.51 across franchises. Similarity finds pairs; only the
// adjudicator (human, or GLO-14's Edge Function) decides the verb.
//
// Idempotent: a pair already in merge_candidates — in either order, in ANY
// state — is never requeued, so a rejected pair stays rejected across runs.
// Within a run, `b.id > a.id` keeps each pair single and canonically ordered.
//
// Usage:
//   deno run --allow-run --allow-env scripts/merge_feeder.ts [--dry-run]
//   deno run --allow-run --allow-env scripts/merge_feeder.ts --pending
//
// --dry-run counts and samples the band without writing; --pending prints the
// current queue (the adjudication surface until GLO-14's function owns it).

const CONTAINER = Deno.env.get("GLOSSED_DB_CONTAINER") ?? "supabase_db_glossed";

// The band floor, from the live distribution (Aug 28 2026): ≥0.5 yields ~364
// reviewable pairs; 0.4–0.5 adds ~273 mostly-noise rows, below that it
// explodes. Queue depth is the canary (tech/01 §4) — raise the floor if the
// queue grows faster than review, don't add an auto-merge band.
const BAND_FLOOR = 0.5;

// Both sides must be live canonical rows: personal-scope products are the
// user's own, merged rows are already settled, delisted rows are gone.
const PAIRS = `
    select a.id as product_a, b.id as product_b,
           similarity(a.normalized_name, b.normalized_name) as sim
    from products a
    join products b on b.brand_id = a.brand_id and b.id > a.id
    where a.scope = 'canonical' and b.scope = 'canonical'
      and a.merged_into is null and b.merged_into is null
      and a.delisted_at is null and b.delisted_at is null
      and similarity(a.normalized_name, b.normalized_name) >= ${BAND_FLOOR}`;

const INSERT = `
with pairs as (${PAIRS}), queued as (
    insert into merge_candidates (product_a, product_b, similarity)
    select p.product_a, p.product_b, p.sim
    from pairs p
    where not exists (
        select 1 from merge_candidates mc
        where (mc.product_a = p.product_a and mc.product_b = p.product_b)
           or (mc.product_a = p.product_b and mc.product_b = p.product_a)
    )
    returning id
)
select count(*) as queued_this_run from queued;`;

const SUMMARY = `
select state, count(*), min(similarity)::numeric(3,2) as lo,
       max(similarity)::numeric(3,2) as hi
from merge_candidates group by state order by state;`;

const PENDING = `
select br.name as brand, a.name as product_a, a.source as src_a,
       b.name as product_b, b.source as src_b,
       mc.similarity::numeric(3,2) as sim
from merge_candidates mc
join products a on a.id = mc.product_a
join products b on b.id = mc.product_b
join brands br on br.id = a.brand_id
where mc.state = 'pending'
order by mc.similarity desc;`;

async function runSQL(statements: string): Promise<string> {
  const psql = new Deno.Command("docker", {
    args: ["exec", "-i", CONTAINER, "psql", "-U", "postgres", "-d", "postgres", "-q"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = psql.stdin.getWriter();
  await writer.write(new TextEncoder().encode(statements));
  await writer.close();
  const out = await psql.output();
  const stderr = new TextDecoder().decode(out.stderr).trim();
  if (stderr) console.error(stderr.split("\n").slice(0, 20).join("\n"));
  if (!out.success) Deno.exit(1);
  return new TextDecoder().decode(out.stdout);
}

if (Deno.args.includes("--pending")) {
  console.log(await runSQL(PENDING));
  Deno.exit(0);
}

if (Deno.args.includes("--dry-run")) {
  const preview = await runSQL(`
with pairs as (${PAIRS})
select count(*) as in_band,
       count(*) filter (where not exists (
           select 1 from merge_candidates mc
           where (mc.product_a = p.product_a and mc.product_b = p.product_b)
              or (mc.product_a = p.product_b and mc.product_b = p.product_a)
       )) as would_queue
from pairs p;`);
  console.log(`--dry-run: no writes\n${preview}`);
  Deno.exit(0);
}

console.log(await runSQL(INSERT));
console.log(await runSQL(SUMMARY));
