// GLO-48 · the catalog-image pipeline: processed once at ingest, never at
// render (tech/01 §7, ADR 0004).
//
// Consumes the `ingest_jobs(kind='image_fetch')` queue that scripts/
// obf_import.ts fills: download the source photo → background removal via
// scripts/CatalogCutout (Vision on this Mac — the PRD §08 alternative to
// rembg, and the same API the app's on-device cutouts use) → transparent PNG,
// longest side 512 → upload to the `catalog` storage bucket (public read) →
// one `variant_images` row per variant → job marked done.
//
// Storage: Supabase Storage via its REST API. Locally that is `supabase
// start`'s stack; the same script runs against hosted Supabase with the env
// flipped. Moving to R2 later (GLO-48's provisioning) swaps only `upload()` —
// keys and rows are storage-agnostic. Keys are `<variant_id>/cut512.png`
// inside the bucket; the app composes
// `<SUPABASE_URL>/storage/v1/object/public/catalog/<key>`.
//
// Claiming uses the state-filtered UPDATE that is the project's one queue
// lock (see feed_diff — do not "improve" it into select-then-update).
//
// Usage:
//   SUPABASE_SERVICE_ROLE_KEY=... deno run --allow-net --allow-run --allow-env \
//     --allow-read --allow-write scripts/catalog_images.ts [--limit N] [--batch N]

const USER_AGENT = "Glossed-Dev/0.1 (seanbrasse@gmail.com)";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CONTAINER = Deno.env.get("GLOSSED_DB_CONTAINER") ?? "supabase_db_glossed";
const BUCKET = "catalog";
const MAX_DIMENSION = 512;
const TOOL = "scripts/CatalogCutout/.build/release/CatalogCutout";

if (!SERVICE_KEY) {
  console.error("SUPABASE_SERVICE_ROLE_KEY is required (from `supabase status` locally)");
  Deno.exit(1);
}

const limitArg = Deno.args.indexOf("--limit");
const jobLimit = limitArg >= 0 ? Number(Deno.args[limitArg + 1]) : Infinity;
const batchArg = Deno.args.indexOf("--batch");
const batchSize = batchArg >= 0 ? Number(Deno.args[batchArg + 1]) : 25;

async function psql(statements: string): Promise<string> {
  const child = new Deno.Command("docker", {
    args: ["exec", "-i", CONTAINER, "psql", "-U", "postgres", "-d", "postgres", "-q", "-t", "-A", "-F", "\t"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(statements));
  await writer.close();
  const out = await child.output();
  const stderr = new TextDecoder().decode(out.stderr).trim();
  if (stderr) console.error(stderr.split("\n").slice(0, 10).join("\n"));
  return new TextDecoder().decode(out.stdout);
}

async function ensureTool() {
  try {
    await Deno.stat(TOOL);
  } catch {
    console.log("building CatalogCutout…");
    const build = await new Deno.Command("swift", {
      args: ["build", "-c", "release", "--package-path", "scripts/CatalogCutout"],
    }).output();
    if (!build.success) {
      console.error(new TextDecoder().decode(build.stderr));
      Deno.exit(1);
    }
  }
}

/// Public-read bucket for catalog images. 409 means it already exists.
async function ensureBucket() {
  const response = await fetch(`${SUPABASE_URL}/storage/v1/bucket`, {
    method: "POST",
    headers: { authorization: `Bearer ${SERVICE_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ id: BUCKET, name: BUCKET, public: true }),
  });
  if (response.ok) {
    await response.body?.cancel();
    return;
  }
  // "Already exists" arrives as HTTP 400 wrapping a 409 code, not as a 409.
  const body = await response.text();
  if (response.status !== 409 && !body.includes("BucketAlreadyExists")) {
    console.error(`bucket create failed: ${response.status} ${body}`);
    Deno.exit(1);
  }
}

interface Job {
  id: string;
  variantID: string;
  url: string;
}

async function claim(count: number): Promise<Job[]> {
  const rows = await psql(`
update ingest_jobs
   set state = 'running', attempts = attempts + 1, updated_at = now()
 where id in (
       select id from ingest_jobs
        where kind = 'image_fetch' and state = 'queued' and run_after <= now()
        order by created_at
        limit ${count}
          for update skip locked)
returning id, payload->>'variant_id', payload->>'url';`);
  return rows
    .split("\n")
    .filter((line) => line.includes("\t"))
    .map((line) => {
      const [id, variantID, url] = line.split("\t");
      return { id, variantID, url };
    });
}

async function finish(job: Job, key: string, width: number, height: number) {
  await psql(`
insert into variant_images (variant_id, kind, r2_key, width, height, image_source, last_fetched)
select '${job.variantID}', 'catalog', $k$${key}$k$, ${width}, ${height}, $u$${job.url}$u$, now()
where not exists (select 1 from variant_images where variant_id = '${job.variantID}' and kind = 'catalog');
update ingest_jobs set state = 'done', updated_at = now() where id = '${job.id}';`);
}

async function fail(job: Job, reason: string) {
  const tidy = reason.replaceAll("$", "").slice(0, 300);
  await psql(`
update ingest_jobs
   set state = case when attempts >= 3 then 'dead' else 'failed' end,
       last_error = $e$${tidy}$e$, updated_at = now()
 where id = '${job.id}';`);
}

async function process(job: Job, scratch: string): Promise<boolean> {
  // One host per source rung (GLO-79). Anything else in the queue is a bug
  // or an injection, and downloading it would be the wrong response to both.
  const allowedHosts = ["https://images.openbeautyfacts.org/", "https://cdn.shopify.com/"];
  if (!allowedHosts.some((host) => job.url.startsWith(host))) {
    await fail(job, `unexpected image host: ${job.url}`);
    return false;
  }
  const raw = `${scratch}/${job.variantID}.src`;
  const cut = `${scratch}/${job.variantID}.png`;
  const response = await fetch(job.url, { headers: { "user-agent": USER_AGENT } });
  if (!response.ok) {
    await fail(job, `download HTTP ${response.status}`);
    return false;
  }
  await Deno.writeFile(raw, new Uint8Array(await response.arrayBuffer()));

  const tool = await new Deno.Command(TOOL, {
    args: [raw, cut, String(MAX_DIMENSION)],
    stdout: "piped",
    stderr: "piped",
  }).output();
  // 4 = a person in frame. Not retryable — the source photo is the problem,
  // and the drawn mock is the honest floor until a studio image exists
  // (the source ladder, GLO-79). Straight to dead so re-runs skip it.
  if (tool.code === 4) {
    await psql(`
update ingest_jobs set state = 'dead',
       last_error = 'person in frame — needs a studio source (GLO-79)', updated_at = now()
 where id = '${job.id}';`);
    return false;
  }
  // 0 = cut, 3 = uncut fallback — both wrote a usable PNG.
  if (tool.code !== 0 && tool.code !== 3) {
    await fail(job, `cutout: ${new TextDecoder().decode(tool.stderr).trim()}`);
    return false;
  }
  const [size] = new TextDecoder().decode(tool.stdout).trim().split(" ");
  const [width, height] = size.split("x").map(Number);

  const key = `${job.variantID}/cut512.png`;
  const upload = await fetch(`${SUPABASE_URL}/storage/v1/object/${BUCKET}/${key}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${SERVICE_KEY}`,
      "content-type": "image/png",
      "x-upsert": "true",
    },
    body: await Deno.readFile(cut),
  });
  if (!upload.ok) {
    await fail(job, `upload HTTP ${upload.status}: ${await upload.text()}`);
    return false;
  }
  await upload.body?.cancel();
  await finish(job, key, width, height);
  return true;
}

await ensureTool();
await ensureBucket();
const scratch = await Deno.makeTempDir({ prefix: "glossed-catalog-images-" });

let done = 0;
let failed = 0;
while (done + failed < jobLimit) {
  const jobs = await claim(Math.min(batchSize, jobLimit - done - failed));
  if (jobs.length === 0) break;
  for (const job of jobs) {
    try {
      (await process(job, scratch)) ? done++ : failed++;
    } catch (error) {
      await fail(job, String(error));
      failed++;
    }
    if ((done + failed) % 25 === 0) console.log(`…${done} done, ${failed} failed`);
  }
}

console.log(`\n${done} images processed, ${failed} failed`);
console.log(await psql(`
select state, count(*) from ingest_jobs where kind = 'image_fetch' group by state order by state;`));
