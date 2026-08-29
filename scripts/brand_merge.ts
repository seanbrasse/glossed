// GLO-106 · Curated brand consolidation — one house, one row.
//
// The catalog acquired the same house under several spellings because
// normalize_name() keeps accents apart ("loréal paris" ≠ "loreal paris") and
// each source wrote its own casing. Search already bridges them per-token,
// but brand-grouped surfaces (shelf sort by brand, the near-match brand
// band) treat them as different houses — which they are not.
//
// CURATED, never inferred: the wrong-franchise trap (GLO-85) is exactly what
// an automatic brand matcher would fall into (hue/dew, homme/femme). Every
// merge below is a human-readable claim, and the script refuses any move
// that would collide two products of the same normalized name — those pairs
// are queued into merge_candidates for adjudication instead (never lost,
// never auto-merged).
//
// Idempotent: merged losers are gone on the next run; renames re-apply as
// no-ops.
//
// Run: deno run --allow-run --allow-env scripts/brand_merge.ts [--dry-run]

const CONTAINER = Deno.env.get("GLOSSED_DB_CONTAINER") ?? "supabase_db_glossed";
const dryRun = Deno.args.includes("--dry-run");

/// winner normalized_name ← loser normalized_names.
const MERGES: Record<string, string[]> = {
  "loréal paris": ["loréal", "loreal consumer products", "loreal paris"],
  "maybelline": ["gemey maybelline", "maybelline new york"],
};

/// Display-name fixes: rows whose casing predates the canonical writer
/// (an insert conflict keeps the old name). normalized_name → display name.
const RENAMES: Record<string, string> = {
  "cosrx": "cosrx",
  "la roche posay": "la roche-posay",
  "loréal paris": "l'oréal paris",
  "maybelline": "maybelline",
};

function quote(raw: string): string {
  return `$glossed$${raw}$glossed$`;
}

async function psql(sql: string): Promise<string> {
  const run = await new Deno.Command("docker", {
    args: ["exec", "-i", CONTAINER, "psql", "-U", "postgres", "-d", "postgres", "-tA", "-c", sql],
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (run.code !== 0) {
    throw new Error(new TextDecoder().decode(run.stderr));
  }
  return new TextDecoder().decode(run.stdout).trim();
}

for (const [winner, losers] of Object.entries(MERGES)) {
  const winnerID = await psql(
    `select id from brands where normalized_name = ${quote(winner)};`,
  );
  if (winnerID.length === 0) {
    console.log(`SKIP ${winner}: no winner row`);
    continue;
  }
  for (const loser of losers) {
    const loserID = await psql(
      `select id from brands where normalized_name = ${quote(loser)};`,
    );
    if (loserID.length === 0) {
      console.log(`  ${loser}: already merged`);
      continue;
    }
    if (dryRun) {
      const movable = await psql(`
select count(*) from products l
where l.brand_id = '${loserID}'
  and not exists (
      select 1 from products w
      where w.brand_id = '${winnerID}' and w.normalized_name = l.normalized_name
  );`);
      const wouldCollide = await psql(`
select count(*) from products l
join products w on w.normalized_name = l.normalized_name and w.brand_id = '${winnerID}'
where l.brand_id = '${loserID}';`);
      console.log(`  DRY ${loser} → ${winner}: ${movable} move, ${wouldCollide} to adjudication`);
      continue;
    }

    // Products whose name already exists under the winner cannot move — they
    // are probable duplicates of the winner's row, so they go to the
    // adjudication queue and stay where they are until a verdict.
    const collisions = await psql(`
insert into merge_candidates (product_a, product_b, similarity, verb)
select w.id, l.id, 1.0, 'brand-merge collision (GLO-106)'
from products l
join products w on w.normalized_name = l.normalized_name
   and w.brand_id = '${winnerID}'
where l.brand_id = '${loserID}'
  and not exists (
      select 1 from merge_candidates mc
      where (mc.product_a = w.id and mc.product_b = l.id)
         or (mc.product_a = l.id and mc.product_b = w.id)
  )
returning 1;`).then((rows) => rows.split("\n").filter((r) => r === "1").length);

    const moved = await psql(`
update products l set brand_id = '${winnerID}'
where l.brand_id = '${loserID}'
  and not exists (
      select 1 from products w
      where w.brand_id = '${winnerID}' and w.normalized_name = l.normalized_name
  )
returning 1;`).then((rows) => rows.split("\n").filter((r) => r === "1").length);

    const remaining = await psql(
      `select count(*) from products where brand_id = '${loserID}';`,
    );
    if (remaining === "0") {
      await psql(`delete from brands where id = '${loserID}';`);
      console.log(`  ${loser} → ${winner}: ${moved} moved, ${collisions} queued, row deleted`);
    } else {
      console.log(
        `  ${loser} → ${winner}: ${moved} moved, ${collisions} queued, ` +
          `${remaining} colliding rows HELD (brand row kept until adjudicated)`,
      );
    }
  }
}

if (!dryRun) {
  for (const [normalized, display] of Object.entries(RENAMES)) {
    await psql(
      `update brands set name = ${quote(display)} where normalized_name = ${quote(normalized)};`,
    );
  }
  console.log("display names aligned to house style");
}
