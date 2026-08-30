// storage_presign — short-lived PUT URLs for user uploads on R2.
//
// The app never holds an R2 credential (ADR 0004). It asks here, we check the
// caller actually owns the item, and we hand back a URL that only works for
// that one object, that one content type, and that one byte count, for five
// minutes.
//
// Two layers of auth, deliberately: the platform's `verify_jwt` (on by default)
// rejects anything without a valid session before this file runs, and the
// ownership check below runs under the caller's own JWT so the database — not
// this handler — decides whether the caller may write.
//
// TWO NAMESPACES, ONE FUNCTION (tech/02 §5, GLO-132). `user_item_id` asks for a
// cutout; `variant_id` asks for a swatch. The signing, the size cap and the
// accepted content types are the same problem twice, so they are one
// implementation; the gates differ and are named separately below.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  cutoutKey,
  lookKey,
  PRESIGN_TTL_SECONDS,
  presignPut,
  r2Config,
  resolvePublishableKey,
  swatchKey,
  validate,
  validateLook,
  validateSwatch,
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

  // Exactly one id decides the namespace. Accepting more than one would leave
  // the key shape depending on evaluation order rather than on the request.
  const wantsSwatch = body.variant_id !== undefined;
  const wantsCutout = body.user_item_id !== undefined;
  const wantsLook = body.look_id !== undefined;
  if ([wantsSwatch, wantsCutout, wantsLook].filter(Boolean).length !== 1) {
    return json({ error: "exactly one of user_item_id, variant_id or look_id is required" }, 400);
  }

  const input = {
    userItemID: body.user_item_id as string,
    variantID: body.variant_id as string,
    lookID: body.look_id as string,
    position: body.position as number,
    contentType: body.content_type as string,
    contentLength: body.content_length as number,
  };
  const rejection = wantsSwatch
    ? validateSwatch(input)
    : wantsLook
    ? validateLook(input)
    : validate(input);
  if (rejection) return json({ error: rejection }, 400);

  try {
    const supabase = createClient(env("SUPABASE_URL") ?? "", resolvePublishableKey(env), {
      global: { headers: { Authorization: authorization } },
    });

    const { data: { user } } = await supabase.auth.getUser(
      authorization.replace("Bearer ", ""),
    );
    if (!user) return json({ error: "unauthenticated" }, 401);

    let key: string;

    if (wantsSwatch) {
      // THE SAME PREDICATE THE INSERT POLICY USES, not a reimplementation of
      // it. can_post_swatch() (migration 0026) encodes both write gates —
      // minors cannot post at all, and you may only swatch a variant on your
      // own shelf — and swatches_insert_own calls the identical function. The
      // upload happens before the row exists, so the rule needs enforcing in
      // two places; naming one function is what stops the two from drifting.
      //
      // It runs under the caller's JWT and is a definer wrapper answering only
      // about auth.uid(), so it reveals nothing the caller could not learn by
      // attempting the insert.
      const { data: allowed, error } = await supabase
        .rpc("can_post_swatch", { p_variant: input.variantID });
      if (error) throw error;

      // ONE REFUSAL FOR BOTH GATES, deliberately. A minor and a stranger to
      // this variant get byte-identical responses. Distinguishing them would
      // turn this endpoint into an oracle for "is that account a minor?",
      // which is precisely what the minors lock exists to prevent — and the
      // caller loses nothing, because neither of them may upload.
      if (!allowed) return json({ error: "not allowed for this variant" }, 403);

      key = swatchKey(user.id, input.variantID, input.contentType);
    } else if (wantsLook) {
      // Same doctrine as swatches: the SAME predicates the insert policies
      // use, not a reimplementation. can_post_look() (0043) is the minor
      // gate; the owner check is RLS answering a select on the caller's own
      // draft. One refusal for both — a minor and a stranger to this look
      // get byte-identical responses, so this endpoint is not an oracle for
      // "is that account a minor?".
      const { data: allowed, error } = await supabase.rpc("can_post_look");
      if (error) throw error;
      const { data: look } = await supabase
        .from("looks")
        .select("id")
        .eq("id", input.lookID)
        .maybeSingle();
      if (!allowed || !look) return json({ error: "not allowed for this look" }, 403);

      key = lookKey(user.id, input.lookID, input.position, input.contentType);
    } else {
      // Under the caller's JWT, so RLS answers this — a row belonging to someone
      // else comes back as no row, not as a denied read we would have to notice.
      const { data: item } = await supabase
        .from("user_items")
        .select("id")
        .eq("id", input.userItemID)
        .is("deleted_at", null)
        .maybeSingle();
      if (!item) return json({ error: "no such item" }, 404);

      key = cutoutKey(user.id, input.userItemID, input.contentType);
    }
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
