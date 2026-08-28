// dedupe_adjudicate — the transport half. Claims pending merge-queue pairs,
// asks Claude for a verdict per pair (budgeted), applies the confident ones,
// leaves the rest for the weekly human pass with the verdict recorded.
//
// The Claude call lives here and only here: LLM calls happen in Edge
// Functions, never the app (root CLAUDE.md), and the spend cap is structural —
// one run costs at most MAX_CALLS_PER_RUN calls whatever the queue holds.

import Anthropic from "npm:@anthropic-ai/sdk@0.121.0";
import { z } from "npm:zod@4.4.3";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@0.121.0/helpers/zod";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { resolveSecretKey } from "../_shared/credentials.ts";
import {
  adjudicationPrompt,
  disposition,
  type FeedRowRecord,
  MAX_CALLS_PER_RUN,
  type ProductRecord,
  stateFor,
  type Verdict,
} from "./adjudicate.ts";

const VerdictSchema = z.object({
  verb: z.enum(["merge", "attach_variant", "fork", "unsure"]),
  confidence: z.number().min(0).max(1),
  reasoning: z.string().max(500),
});

const json = (body: unknown, status: number): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

async function askClaude(anthropic: Anthropic, prompt: string): Promise<Verdict> {
  const response = await anthropic.messages.parse({
    model: "claude-opus-5",
    max_tokens: 2048,
    output_config: { format: zodOutputFormat(VerdictSchema) },
    messages: [{ role: "user", content: prompt }],
  });
  const parsed = response.parsed_output;
  if (!parsed) throw new Error("verdict did not parse");
  return parsed;
}

/** Applies an auto-band verdict for a feed-row pair. Conservative on merge:
 * without a variant-level match the "same product" claim has nowhere safe to
 * write, so it only updates when the match is unambiguous. */
async function applyVerdict(
  db: SupabaseClient,
  pair: { id: string; product_a: string; feed_row: FeedRowRecord },
  verdict: Verdict,
): Promise<string> {
  const row = pair.feed_row;
  switch (verdict.verb) {
    case "merge": {
      // The same product and variant line: refresh the matching variant.
      const { data: variants, error } = await db
        .from("variants")
        .select("id, shade_code")
        .eq("product_id", pair.product_a);
      if (error) throw error;
      const match = row.shade_code
        ? variants?.find((v) => v.shade_code === row.shade_code)
        : (variants?.length === 1 ? variants[0] : undefined);
      if (!match) return "merge had no unambiguous variant — left for a human";
      const { error: updateError } = await db
        .from("variants")
        .update({ source: "feed", last_verified: new Date().toISOString() })
        .eq("id", match.id);
      if (updateError) throw updateError;
      return "merged into existing variant";
    }
    case "attach_variant": {
      const { error } = await db.from("variants").insert({
        product_id: pair.product_a,
        kind: row.shade_code ? "shade" : "default",
        shade_code: row.shade_code ?? null,
        size_ml: row.size_ml ?? null,
        source: "feed",
        last_verified: new Date().toISOString(),
      });
      if (error) throw error;
      return "variant attached";
    }
    case "fork": {
      // A successor keeps the lineage: old keeps its chips and rankings, new
      // starts clean, linked (PRD §15's reformulation rule).
      const { data: parent, error: parentError } = await db
        .from("products")
        .select("brand_id, category_id, domain")
        .eq("id", pair.product_a)
        .single();
      if (parentError) throw parentError;
      const { error } = await db.from("products").insert({
        brand_id: parent.brand_id,
        category_id: parent.category_id,
        domain: parent.domain,
        name: row.name,
        normalized_name: row.name.toLowerCase(),
        scope: "canonical",
        forked_from: pair.product_a,
        source: "feed",
      });
      if (error) throw error;
      return "forked";
    }
    case "unsure":
      return "held";
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const secret = Deno.env.get("INGEST_SECRET");
  if (!secret || req.headers.get("x-ingest-secret") !== secret) {
    return json({ error: "unauthenticated" }, 401);
  }

  let body: { dry_run?: boolean };
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", resolveSecretKey(Deno.env.get));
  const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });

  // Feed-row pairs only for now: product_b pairs (user submissions) get their
  // verdict recorded but no automatic application — that write path involves
  // moving user data between products and stays with the weekly human.
  const { data: pairs, error: claimError } = await db
    .from("merge_candidates")
    .select("id, product_a, feed_row, similarity")
    .eq("state", "pending")
    .not("feed_row", "is", null)
    .order("created_at")
    .limit(MAX_CALLS_PER_RUN);
  if (claimError) return json({ error: "claim failed" }, 500);

  const outcomes: { id: string; verb: string; confidence: number; outcome: string }[] = [];
  for (const pair of pairs ?? []) {
    const { data: product, error: productError } = await db
      .from("products")
      .select("id, name, inci_raw, brands(name), categories(slug)")
      .eq("id", pair.product_a)
      .single();
    if (productError) continue;
    const { data: variants } = await db
      .from("variants")
      .select("shade_code, size_ml")
      .eq("product_id", pair.product_a);

    const record: ProductRecord = {
      id: product.id,
      name: product.name,
      brand_name: (product.brands as unknown as { name: string }).name,
      category_slug: (product.categories as unknown as { slug: string }).slug,
      variants: variants ?? [],
      inci_raw: product.inci_raw,
    };

    try {
      const verdict = await askClaude(anthropic, adjudicationPrompt(record, pair.feed_row));
      const kind = disposition(verdict);
      let outcome = "held";
      if (!body.dry_run) {
        if (kind === "auto_apply") {
          outcome = await applyVerdict(db, pair, verdict);
        }
        await db.from("merge_candidates")
          .update({
            llm_verdict: verdict,
            verb: verdict.verb === "unsure" ? null : verdict.verb,
            state: outcome.startsWith("merge had no") ? "pending" : stateFor(kind),
            decided_by: kind === "auto_apply" ? "claude-opus-5" : null,
            decided_at: kind === "auto_apply" ? new Date().toISOString() : null,
          })
          .eq("id", pair.id);
      }
      outcomes.push({ id: pair.id, verb: verdict.verb, confidence: verdict.confidence, outcome });
    } catch (error) {
      console.error("adjudication failed for", pair.id, error);
      outcomes.push({
        id: pair.id,
        verb: "error",
        confidence: 0,
        outcome: String(error).slice(0, 120),
      });
    }
  }

  return json({ dry_run: body.dry_run ?? false, considered: pairs?.length ?? 0, outcomes }, 200);
});
