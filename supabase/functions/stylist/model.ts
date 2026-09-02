// The Stylist's model half — reached only when plan.ts found no rule for the
// words (index.ts decides). The tool loop against claude-opus-5: data tools
// read under the caller's JWT, artifact tools are validated against the
// prefetch, and the turn stops at MAX_TOOL_CALLS whatever the model wants
// next. Nothing is stored; the SDK error is never echoed (it can carry the
// request, and the request carries the person's skin and shelf).

import Anthropic from "npm:@anthropic-ai/sdk@0.121.0";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { affinity, crosswalk, searchCatalog } from "./data.ts";
import {
  ARTIFACT_TOOLS,
  assembleReply,
  type Block,
  type CatalogHit,
  DATA_TOOLS,
  MAX_TOKENS,
  MAX_TOOL_CALLS,
  MODEL,
  renderContext,
  type Reply,
  type StylistContext,
  systemPrompt,
  TOOLS,
  type TranscriptTurn,
  validateArtifact,
} from "./tools.ts";

type DataResult = { text: string; hits: CatalogHit[] };

async function runDataTool(
  supabase: SupabaseClient,
  name: string,
  input: Record<string, unknown>,
): Promise<DataResult> {
  switch (name) {
    case "search_catalog": {
      const q = typeof input.query === "string" ? input.query.slice(0, 80) : "";
      const domain = typeof input.domain === "string" ? input.domain : null;
      const hits = await searchCatalog(supabase, q, domain);
      const text = hits.length === 0
        ? "no products matched. say so rather than guess."
        : hits.map((h) =>
          `product_id=${h.id} · ${h.brand_name} · ${h.name} · ${h.category_slug} · n=${
            h.n_face_offs ?? 0
          } face-offs`
        ).join("\n");
      return { text, hits };
    }
    case "query_affinity": {
      const rows = await affinity(supabase);
      const text = rows.length === 0
        ? "no affinity yet — this person has not logged enough for a lean. say so."
        : rows.map((r) =>
          `${r.label} · n_signals=${r.n_signals} · score=${Number(r.shrunk_score).toFixed(2)}`
        ).join("\n");
      return { text, hits: [] };
    }
    case "crosswalk": {
      const rows = await crosswalk(supabase, 6);
      const text = rows.length === 0
        ? "no crosswalk — this person has no shade anchor yet, or too few people share it. say so."
        : rows.map((r) =>
          `product_id=${r.id} · ${r.brand_name} · ${r.name} · people who wear ${r.anchor_label} also wear this · n=${r.n}`
        ).join("\n");
      return { text, hits: rows };
    }
    default:
      return { text: `unknown tool ${name}`, hits: [] };
  }
}

export type ModelOutcome =
  | { readonly ok: true; readonly reply: Reply }
  | { readonly ok: false; readonly kind: string; readonly calls: number };

/// `workspaceID`: an identity-linked ("personal") console key is refused
/// without `anthropic-workspace-id` on every request; a workspace key
/// needs none. Both shapes are accepted so the env decides.
export async function runModelTurn(
  apiKey: string,
  workspaceID: string | null,
  supabase: SupabaseClient,
  ctx: StylistContext,
  transcript: readonly TranscriptTurn[],
  userID: string,
): Promise<ModelOutcome> {
  const anthropic = new Anthropic({
    apiKey,
    defaultHeaders: workspaceID ? { "anthropic-workspace-id": workspaceID } : undefined,
  });
  const messages: Anthropic.MessageParam[] = transcript.map((t) => ({
    role: t.role,
    content: t.text,
  }));
  const system: Anthropic.TextBlockParam[] = [
    { type: "text", text: systemPrompt() },
    { type: "text", text: renderContext(ctx), cache_control: { type: "ephemeral" } },
  ];
  const tools: Anthropic.Tool[] = TOOLS.map((t) => ({
    name: t.name,
    description: t.description,
    input_schema: t.input_schema as Anthropic.Tool["input_schema"],
  }));

  const blocks: Block[] = [];
  let chips: string[] = [];
  const toolsUsed: string[] = ["model"];
  const searched = new Map<string, CatalogHit>();
  let text = "";
  let calls = 0;

  const textOf = (content: Anthropic.ContentBlock[]) =>
    content.filter((b): b is Anthropic.TextBlock => b.type === "text").map((b) => b.text).join(
      "\n",
    );

  try {
    while (true) {
      const response = await anthropic.messages.create({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system,
        tools,
        messages,
        output_config: { effort: "low" },
      });
      text = textOf(response.content);
      if (response.stop_reason === "refusal") {
        text = "";
        break;
      }
      if (response.stop_reason !== "tool_use") break;

      const uses = response.content.filter((b): b is Anthropic.ToolUseBlock =>
        b.type === "tool_use"
      );
      messages.push({ role: "assistant", content: response.content });
      const results: Anthropic.ToolResultBlockParam[] = [];
      for (const use of uses) {
        calls += 1;
        toolsUsed.push(use.name);
        const input = (use.input ?? {}) as Record<string, unknown>;
        let content: string;
        let isError = false;
        if (calls > MAX_TOOL_CALLS) {
          content = "tool budget for this turn is spent — answer with what you have.";
          isError = true;
        } else if (DATA_TOOLS.has(use.name)) {
          try {
            const r = await runDataTool(supabase, use.name, input);
            for (const h of r.hits) searched.set(h.id, h);
            content = r.text;
          } catch {
            console.error("stylist data tool failed", { user: userID, tool: use.name });
            content = "that lookup failed — answer without it, and say so.";
            isError = true;
          }
        } else if (ARTIFACT_TOOLS.has(use.name)) {
          const v = validateArtifact(use.name, input, ctx, searched);
          if (v.ok) {
            if (v.block) blocks.push(v.block);
            if (v.chips) chips = [...v.chips];
            content = "shown to the person.";
          } else {
            content = v.error;
            isError = true;
          }
        } else {
          content = `unknown tool ${use.name}`;
          isError = true;
        }
        results.push({
          type: "tool_result",
          tool_use_id: use.id,
          content,
          is_error: isError || undefined,
        });
      }
      messages.push({ role: "user", content: results });
      if (calls > MAX_TOOL_CALLS) {
        // One last, tool-less answer so the person gets words, not a stall.
        const final = await anthropic.messages.create({
          model: MODEL,
          max_tokens: MAX_TOKENS,
          system,
          messages,
          tool_choice: { type: "none" },
          tools,
          output_config: { effort: "low" },
        });
        text = textOf(final.content);
        break;
      }
    }
  } catch (error) {
    const kind = error instanceof Anthropic.RateLimitError
      ? "rate_limited"
      : error instanceof Anthropic.APIError
      ? `api_${error.status}`
      : "unknown";
    return { ok: false, kind, calls };
  }

  return {
    ok: true,
    reply: assembleReply(text, blocks, chips, toolsUsed, [
      "profile",
      "shelf",
      "routines",
      "collections",
      "looks",
    ]),
  };
}
