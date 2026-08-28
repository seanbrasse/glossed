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
import { cutoutKey, PRESIGN_TTL_SECONDS, presignPut, validate } from "./presign.ts";

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

/// The platform injects the publishable key under a name that changed with the
/// new API-key scheme; accept either rather than fail at deploy time.
function publishableKey(): string {
  const legacy = Deno.env.get("SUPABASE_ANON_KEY");
  if (legacy) return legacy;
  const map = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (map) {
    const named = (JSON.parse(map) as Record<string, string>)["default"];
    return Deno.env.get(named) ?? named;
  }
  throw new Error("no publishable key in the function environment");
}

function r2Config() {
  const accountID = Deno.env.get("R2_ACCOUNT_ID");
  const bucket = Deno.env.get("R2_BUCKET");
  const accessKeyID = Deno.env.get("R2_ACCESS_KEY_ID");
  const secretAccessKey = Deno.env.get("R2_SECRET_ACCESS_KEY");
  if (!accountID || !bucket || !accessKeyID || !secretAccessKey) {
    throw new Error("R2 credentials missing from the function environment");
  }
  return { accountID, bucket, accessKeyID, secretAccessKey };
}

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
    const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", publishableKey(), {
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
      r2Config(),
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
