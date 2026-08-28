// track_ingest — the batched analytics write. tech/06 §2.
//
// verify_jwt (platform default) already requires a valid JWT, so the caller
// is our app: signed in (user events) or on the anon key (pre-signup
// onboarding, which is why anon_id exists). The user id comes from the
// token, never the payload — a client cannot file events as someone else.
//
// Writes go through the service client because users hold no grants on
// `events` at all (migration 0011): the one write path is this function, and
// the on-conflict makes a retried batch a no-op.

import { createClient } from "npm:@supabase/supabase-js@2";
import { type IncomingEvent, MAX_BATCH, partition } from "./validate.ts";
import { resolveSecretKey } from "../_shared/credentials.ts";

const json = (body: unknown, status: number): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "unauthenticated" }, 401);

  let body: { events?: IncomingEvent[]; app_version?: string; os_version?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "body must be json" }, 400);
  }
  const batch = body.events ?? [];
  if (batch.length === 0) return json({ accepted: 0, rejected: [] }, 200);
  if (batch.length > MAX_BATCH) return json({ error: "batch too large" }, 400);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  // The caller's identity, read from the token — not trusted from the body.
  const asCaller = createClient(url, resolveSecretKey(Deno.env.get), {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user } } = await asCaller.auth.getUser(
    authorization.replace("Bearer ", ""),
  );

  const { accepted, rejected } = partition(batch, Date.now() / 1000);

  if (accepted.length > 0) {
    const service = createClient(url, resolveSecretKey(Deno.env.get));
    const rows = accepted.map((event) => ({
      client_id: event.id,
      user_id: user?.id ?? null,
      anon_id: user ? null : event.anon_id ?? null,
      name: event.name,
      props: event.props ?? {},
      screen: event.screen ?? null,
      app_version: body.app_version ?? null,
      os_version: body.os_version ?? null,
      ts: new Date(event.ts * 1000).toISOString(),
    }));
    const { error } = await service
      .from("events")
      .upsert(rows, { onConflict: "client_id,ts", ignoreDuplicates: true });
    if (error) {
      console.error("track_ingest insert failed", error);
      return json({ error: "ingest failed" }, 500);
    }
  }

  return json({ accepted: accepted.length, rejected }, 200);
});
