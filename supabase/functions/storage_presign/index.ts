// storage_presign — short-lived PUT URLs for user cutouts on R2.
//
// The app never holds an R2 credential (ADR 0004). It asks here, we check the
// caller actually owns the item, and we hand back a URL that only works for
// that one object, that one content type, and that one byte count, for five
// minutes.
//
// Two layers of auth, deliberately: the platform's `verify_jwt` (on by default)
// rejects anything without a valid session before this file runs, and the
// ownership query below runs under the caller's own JWT so RLS — not this
// handler — decides whether the item is theirs.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  cutoutKey,
  PRESIGN_TTL_SECONDS,
  presignPut,
  r2Config,
  resolvePublishableKey,
  validate,
} from "./presign.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const env = (name: string) => Deno.env.get(name);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "unauthenticated" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "body must be json" }, 400);
  }

  const input = {
    userItemID: body.user_item_id as string,
    contentType: body.content_type as string,
    contentLength: body.content_length as number,
  };
  const rejection = validate(input);
  if (rejection) return json({ error: rejection }, 400);

  try {
    const supabase = createClient(env("SUPABASE_URL") ?? "", resolvePublishableKey(env), {
      global: { headers: { Authorization: authorization } },
    });

    const { data: { user } } = await supabase.auth.getUser(
      authorization.replace("Bearer ", ""),
    );
    if (!user) return json({ error: "unauthenticated" }, 401);

    // Under the caller's JWT, so RLS answers this — a row belonging to someone
    // else comes back as no row, not as a denied read we would have to notice.
    const { data: item } = await supabase
      .from("user_items")
      .select("id")
      .eq("id", input.userItemID)
      .is("deleted_at", null)
      .maybeSingle();
    if (!item) return json({ error: "no such item" }, 404);

    const key = cutoutKey(user.id, input.userItemID, input.contentType);
    const url = await presignPut(
      r2Config(env),
      key,
      input.contentType,
      input.contentLength,
    );

    return json({ url, key, expires_in: PRESIGN_TTL_SECONDS }, 200);
  } catch (error) {
    // The message can name a missing secret, so it stays in the logs.
    console.error("storage_presign failed", error);
    return json({ error: "presign failed" }, 500);
  }
});
