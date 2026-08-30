// Where the catalog scripts write. GLO-209.
//
// Every script here built its own `docker exec -i <container> psql -U postgres
// -d postgres …`, which meant the whole catalog pipeline could only ever write
// to this machine. That is why the hosted database has 0 brands, 0 products and
// 0 variants against 3,206 locally — not because nobody ran the importers, but
// because running them somewhere else was not expressible.
//
// STILL VIA DOCKER, DELIBERATELY. The container is the source of the `psql`
// BINARY, not the destination: psql is not installed on this machine at all
// (`command not found`), so a helper that shelled a local psql would work for
// nobody here. The container's psql connects wherever it is pointed.
//
//   unset            → the local supabase container, exactly as before
//   GLOSSED_DB_URL   → that connection string, from inside the container
//
// So the local path is byte-identical to what these scripts did before, and a
// remote run is one environment variable.

/** The container that supplies the psql binary — and, unless GLOSSED_DB_URL is
 * set, also the database being written to. */
export const CONTAINER = Deno.env.get("GLOSSED_DB_CONTAINER") ?? "supabase_db_glossed";

/** A connection string to write to instead of the container's own database.
 * Read once at module load so a script cannot half-target two databases. */
export const DB_URL = Deno.env.get("GLOSSED_DB_URL") ?? null;

/**
 * `docker` arguments for a psql run, with `extra` appended after the target.
 *
 * Callers pass only their own flags (-q, -tA, -c …) and never the connection,
 * which is the point: a script that spelled the connection itself is a script
 * that can be pointed at the wrong database by editing the wrong line.
 */
export function psqlArgs(extra: string[]): string[] {
  const target = DB_URL ? [DB_URL] : ["-U", "postgres", "-d", "postgres"];
  return ["exec", "-i", CONTAINER, "psql", ...target, ...extra];
}

/**
 * One line naming the destination, for a script to print before it writes.
 *
 * A catalog import that says nothing about where it is going is how 3,000 rows
 * end up in the wrong database. The URL is redacted to host and database —
 * these run in terminals people paste from, and a connection string carries a
 * password.
 */
export function targetLabel(): string {
  if (!DB_URL) return `local container ${CONTAINER}`;
  try {
    const u = new URL(DB_URL);
    return `REMOTE ${u.hostname}${u.pathname} (via ${CONTAINER})`;
  } catch {
    return `REMOTE (unparseable GLOSSED_DB_URL, via ${CONTAINER})`;
  }
}

// GLO-223 — a script that GREW the catalog leaves a fresh snapshot behind.
//
// The snapshot was only ever taken when someone ran `make db-reset` or
// remembered `make catalog-snapshot`, so it aged out the moment the catalog
// grew: the protection was newest right after a reset and staler every import
// after it. This is the refresh made automatic.
//
// The hook belongs HERE, in db.ts, and not in the eight import scripts, for
// the same reason the connection does: a script cannot reach the catalog
// without importing this module, so a catalog script written next year is
// covered without anyone remembering to wire it up.
//
// What it deliberately does NOT do: fire for a remote target (GLOSSED_DB_URL
// snapshots the wrong database), fire when the row count did not move (so
// --dry-run and read-only runs cost one count and nothing else), or survive a
// SIGINT — `unload` does not run when the process is killed, which is why
// `make catalog-snapshot` stays the explicit door.
const SNAPSHOT_SH = decodeURIComponent(new URL("./catalog_snapshot.sh", import.meta.url).pathname);

/** The catalog's total row count, or null when it cannot be read. Synchronous
 * on purpose: an `unload` handler cannot await, so both ends must be sync. */
function catalogRows(): number | null {
  try {
    const out = new Deno.Command("bash", { args: [SNAPSHOT_SH, "count"], stderr: "null" })
      .outputSync();
    if (!out.success) return null;
    const n = Number(new TextDecoder().decode(out.stdout).trim());
    return Number.isFinite(n) ? n : null;
  } catch {
    return null;
  }
}

if (!DB_URL) {
  const before = catalogRows();
  globalThis.addEventListener("unload", () => {
    const after = catalogRows();
    if (before === null || after === null || before === after) return;
    console.log(`→ catalog changed ${before} → ${after} rows, refreshing the snapshot`);
    // Inherited stdio: a refusal from the regression guard has to be READ, and
    // a snapshot that failed silently is the bug this whole ticket is about.
    new Deno.Command("bash", { args: [SNAPSHOT_SH, "save"], stderr: "inherit", stdout: "inherit" })
      .outputSync();
  });
}
