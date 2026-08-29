// GLO-104 · Requalify the existing OBF images against the standard.
//
// Sean's ruling (Aug 29): OBF images only when they meet our standards. The
// forward gate lives in catalog_images.ts (source short side ≥ 800px); this
// one-off pass holds the EXISTING OBF-sourced rows to the same bar — refetch
// each source, measure, and delete the row (and its stored cutout) when the
// source is under the floor or gone. A deleted row falls back to the drawn
// mock, which is the chain's honest floor.
//
// Idempotent: a second run finds only survivors and re-verifies them.
//
// Run: SUPABASE_SERVICE_ROLE_KEY=<legacy JWT> deno run --allow-net \
//        --allow-run --allow-env --allow-read --allow-write scripts/obf_requalify.ts

const USER_AGENT = "Glossed-Dev/0.1 (seanbrasse@gmail.com)";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CONTAINER = Deno.env.get("GLOSSED_DB_CONTAINER") ?? "supabase_db_glossed";
const BUCKET = "catalog";
const OBF_HOST = "https://images.openbeautyfacts.org/";
const MIN_SOURCE_SIDE = 800;
const FETCH_INTERVAL_MS = 150;

if (SERVICE_KEY.length === 0) {
  console.error("SUPABASE_SERVICE_ROLE_KEY is required (the legacy JWT — see HANDOFF §9)");
  Deno.exit(1);
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

interface Row {
  id: string;
  key: string;
  url: string;
}

const rows: Row[] = (await psql(`
select id || '|' || r2_key || '|' || image_source
from variant_images
where kind = 'catalog' and image_source like '${OBF_HOST}%';`))
  .split("\n")
  .filter((line) => line.length > 0)
  .map((line) => {
    const [id, key, ...rest] = line.split("|");
    return { id, key, url: rest.join("|") };
  });

console.log(`${rows.length} OBF-sourced images to requalify (floor: ${MIN_SOURCE_SIDE}px)`);

let kept = 0;
let purged = 0;
const scratch = await Deno.makeTempDir();

for (const row of rows) {
  let verdict = "purge";
  let detail = "source gone";
  try {
    const response = await fetch(row.url, { headers: { "user-agent": USER_AGENT } });
    if (response.ok) {
      const file = `${scratch}/probe.img`;
      await Deno.writeFile(file, new Uint8Array(await response.arrayBuffer()));
      const probe = await new Deno.Command("sips", {
        args: ["-g", "pixelWidth", "-g", "pixelHeight", file],
        stdout: "piped",
        stderr: "piped",
      }).output();
      const text = new TextDecoder().decode(probe.stdout);
      const w = Number(text.match(/pixelWidth: (\d+)/)?.[1] ?? 0);
      const h = Number(text.match(/pixelHeight: (\d+)/)?.[1] ?? 0);
      detail = `${w}x${h}`;
      if (Math.min(w, h) >= MIN_SOURCE_SIDE) {
        verdict = "keep";
      }
    } else {
      detail = `HTTP ${response.status}`;
      await response.body?.cancel();
    }
  } catch (error) {
    detail = String(error).slice(0, 80);
  }

  if (verdict === "keep") {
    kept += 1;
  } else {
    await psql(`delete from variant_images where id = '${row.id}';`);
    const removal = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET}/${row.key}`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${SERVICE_KEY}` },
    });
    await removal.body?.cancel();
    purged += 1;
    console.log(`  purged ${row.key} (${detail})`);
  }
  await new Promise((resolve) => setTimeout(resolve, FETCH_INTERVAL_MS));
}

console.log(`\nkept ${kept} (met the standard) · purged ${purged} — mocks are the floor until better sources`);
