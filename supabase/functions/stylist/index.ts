// The Stylist (docs/tech/08-stylist.md) — the transport half. Authenticates
// the caller, prefetches their context UNDER THEIR OWN JWT (RLS is the
// sandbox), and answers once. Nothing is stored.
//
// Data first, model last (Sean, Sept 2): plan.ts reads the words and the
// context and answers the shaped asks — a routine from the shelf, the gaps,
// what to try next, a comparison — from rules and the cohort RPCs. The model
// (model.ts) is reached only for a free-form question no rule covers, and
// only when a key exists; without one the person gets the honest menu, not
// a 503. A turn therefore costs zero model calls in the common case.
//
// Logging discipline is moderate_text's: the messages and the context hold
// regulated data (skin, hair, fit), so no log line carries text —
// identifiers, tool names and counts only.

import { createClient } from "npm:@supabase/supabase-js@2";
import { resolvePublishableKey } from "../_shared/credentials.ts";
import { prefetch, runFetches } from "./data.ts";
import { runModelTurn } from "./model.ts";
import { planTurn } from "./plan.ts";
import { type TranscriptTurn, trimTranscript } from "./tools.ts";

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

  let body: { messages?: TranscriptTurn[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "body must be json" }, 400);
  }
  const transcript = trimTranscript(Array.isArray(body.messages) ? body.messages : []);
  if (transcript.length === 0) {
    return json({ error: "messages must end with something the user said" }, 400);
  }

  const supabase = createClient(env("SUPABASE_URL") ?? "", resolvePublishableKey(env), {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user } } = await supabase.auth.getUser(authorization.replace("Bearer ", ""));
  if (!user) return json({ error: "unauthenticated" }, 401);

  const started = Date.now();
  let fetched;
  try {
    fetched = await prefetch(supabase, user.id);
  } catch {
    console.error("stylist prefetch failed", { user: user.id });
    return json({ error: "couldn't read your shelf just now" }, 502);
  }
  if (!fetched.adult) {
    return json({ error: "not_yet", reason: "the stylist is for adults for now" }, 403);
  }

  const asked = transcript[transcript.length - 1].text;
  const plan = planTurn(asked, fetched);
  let reply;
  if (plan.intent.kind === "open" && env("ANTHROPIC_API_KEY")) {
    const outcome = await runModelTurn(
      env("ANTHROPIC_API_KEY")!,
      supabase,
      fetched.ctx,
      transcript,
      user.id,
    );
    if (!outcome.ok) {
      console.error("stylist turn failed", {
        user: user.id,
        kind: outcome.kind,
        calls: outcome.calls,
      });
      return json({ error: "the stylist couldn't answer just now" }, 502);
    }
    reply = outcome.reply;
  } else {
    const results = await runFetches(supabase, plan.fetches, user.id);
    reply = plan.finish(results);
  }

  console.log("stylist turn", {
    user: user.id,
    intent: plan.intent.kind,
    tools: reply.tools_used,
    blocks: reply.blocks.length,
    ms: Date.now() - started,
  });
  return json(reply, 200);
});
