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
