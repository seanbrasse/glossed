// moderate_text — the transport half. Claims pending public_texts rows, asks
// Claude to classify each, writes the decision back.
//
// The Claude call lives here and only here: LLM calls happen in Edge Functions,
// never the app (root CLAUDE.md). The spend cap is structural — one run costs
// at most MAX_CALLS_PER_RUN calls whatever the queue holds.
//
// THE BODY IS NEVER LOGGED (tech/02 §2.3, root CLAUDE.md). Not on success, not
// on failure, not in an error message. Every log line here carries the row id,
// the kind, the verdict and a short body fingerprint — enough to audit a
// decision, never enough to reconstruct what someone wrote.

import Anthropic from "npm:@anthropic-ai/sdk@0.121.0";
import { z } from "npm:zod@4.4.3";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@0.121.0/helpers/zod";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { resolveSecretKey } from "../_shared/credentials.ts";
import {
  bodyFingerprint,
  disposition,
  MAX_CALLS_PER_RUN,
  moderationPrompt,
  stateFor,
  systemPrompt,
  type TextKind,
  type Verdict,
} from "./moderate.ts";

// The SDK strips JSON-Schema constraints structured outputs does not support
// (minimum/maximum/maxLength) before sending, records them in the field
// description, and still validates the response against the schema as written
// here. So the bounds below are real validation, not decoration.
const VerdictSchema = z.object({
  category: z.enum([
    "clean",
    "harassment",
    "hate",
    "sexual",
    "self_harm",
    "impersonation",
    "spam",
    "contact_details",
    "underage",
    "other",
  ]),
  confidence: z.number().min(0).max(1),
  reasoning: z.string().max(300),
});

const MODEL = "claude-opus-5";

const json = (body: unknown, status: number): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

async function classify(
  anthropic: Anthropic,
  kind: TextKind,
  body: string,
): Promise<Verdict> {
  const response = await anthropic.messages.parse({
    model: MODEL,
    max_tokens: 512,
    system: systemPrompt(),
    output_config: { format: zodOutputFormat(VerdictSchema) },
    messages: [{ role: "user", content: moderationPrompt(kind, body) }],
  });
  const parsed = response.parsed_output;
  if (!parsed) throw new Error("verdict did not parse");
  return parsed;
}

/** Writes the decision. `pending` rows are written too — the verdict and model
 * are recorded even when the disposition is to hold, because a reviewer opening
 * the Studio queue (§7, moderation v0) needs to see what the model thought and
 * why it did not act. A held row with an empty verdict tells them nothing. */
async function recordDecision(
  db: SupabaseClient,
  id: string,
  verdict: Verdict,
  fingerprint: string,
): Promise<string> {
  const state = stateFor(disposition(verdict));
  const { error } = await db
    .from("public_texts")
    .update({
      state,
      model: MODEL,
      verdict: { ...verdict, body_sha256_16: fingerprint },
      decided_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);
  if (error) throw error;
  return state;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const secret = Deno.env.get("INGEST_SECRET");
  if (!secret || req.headers.get("x-ingest-secret") !== secret) {
    return json({ error: "unauthenticated" }, 401);
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    resolveSecretKey(Deno.env.get),
  );
  const anthropic = new Anthropic({
    apiKey: Deno.env.get("ANTHROPIC_API_KEY"),
  });

  // Oldest first. A queue that serves newest-first starves its own backlog, and
  // the person whose bio has been invisible longest is the one waiting.
  const { data: rows, error: claimError } = await db
    .from("public_texts")
    .select("id, kind, body")
    .eq("state", "pending")
    .is("decided_at", null)
    // linked_social has no read path anywhere (GLO-189) — no RPC returns one
    // and public_profile has no field for it. Classifying it spends a Claude
    // call per save on text nobody will ever see. Remove this filter when a
    // surface renders them.
    .neq("kind", "linked_social")
    // `handle` is no longer written at all (GLO-191) — a handle is checked
    // synchronously at claim time, not reviewed afterwards. The filter stays
    // for the rows this queue could still be holding when the migration lands
    // mid-run, and because a rejected handle has nothing to act on: there is
    // no release, rename or re-claim flow to trigger.
    .neq("kind", "handle")
    .order("created_at")
    .limit(MAX_CALLS_PER_RUN);
  if (claimError) return json({ error: "claim failed" }, 500);

  const outcomes: {
    id: string;
    kind: string;
    state: string;
    category: string;
  }[] = [];
  let failures = 0;

  for (const row of rows ?? []) {
    const fingerprint = await bodyFingerprint(row.body);
    try {
      const verdict = await classify(anthropic, row.kind as TextKind, row.body);
      const state = await recordDecision(db, row.id, verdict, fingerprint);
      outcomes.push({
        id: row.id,
        kind: row.kind,
        state,
        category: verdict.category,
      });
    } catch (_e) {
      // FAIL CLOSED, and quietly. The row keeps state='pending', which renders
      // nothing (§3.2), so a model outage delays publication rather than
      // leaking unmoderated text — the one failure mode that must not exist.
      //
      // The caught error is deliberately not logged: an SDK error can echo the
      // request back, and the request contains the body.
      failures++;
      console.error(
        `moderate_text: classify failed id=${row.id} kind=${row.kind} fp=${fingerprint}`,
      );
    }
  }

  return json({
    considered: rows?.length ?? 0,
    decided: outcomes.length,
    failures,
    outcomes,
  }, 200);
});
