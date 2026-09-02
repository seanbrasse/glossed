// The Stylist (docs/tech/08-stylist.md) — the transport half. Authenticates
// the caller, prefetches their context UNDER THEIR OWN JWT (RLS is the
// sandbox), runs the tool loop against claude-opus-5, validates every
// artifact against what was fetched, and answers once. Nothing is stored.
//
// Logging discipline is moderate_text's, not dedupe_adjudicate's: the
// messages and the context hold regulated data (skin, hair, fit), so no log
// line carries text — identifiers, tool names and counts only, and an SDK
// error is never echoed because it can carry the request back.

import Anthropic from "npm:@anthropic-ai/sdk@0.121.0";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { resolvePublishableKey } from "../_shared/credentials.ts";
import {
  ARTIFACT_TOOLS,
  assembleReply,
  type Block,
  type CatalogHit,
  DATA_TOOLS,
  isAdult,
  MAX_TOKENS,
  MAX_TOOL_CALLS,
  MODEL,
  renderContext,
  type StylistContext,
  systemPrompt,
  TOOLS,
  type TranscriptTurn,
  trimTranscript,
  validateArtifact,
} from "./tools.ts";

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

async function prefetch(
  supabase: SupabaseClient,
  userID: string,
): Promise<{ ctx: StylistContext; adult: boolean }> {
  const [profile, shelf, routines, collections, looks] = await Promise.all([
    supabase.from("profiles")
      .select("skin_type,concerns,hair_pattern,domains,climate,birth_year_month")
      .eq("user_id", userID).maybeSingle(),
    supabase.from("user_shelf_items")
      .select(
        "user_item_id,product_id,product_name,brand_name,category_slug,category_label,domain,status,rank_position,ranked_in_category",
      )
      .eq("user_id", userID),
    supabase.from("routines").select("id,title,slot").eq("user_id", userID).is("deleted_at", null),
    supabase.from("collections").select("id,title").eq("user_id", userID).is("deleted_at", null),
    supabase.from("looks").select("id,caption,state").eq("user_id", userID),
  ]);
  for (const r of [profile, shelf, routines, collections, looks]) {
    if (r.error) throw r.error;
  }
  const routineIDs = (routines.data ?? []).map((r) => r.id as string);
  const collectionIDs = (collections.data ?? []).map((c) => c.id as string);
  const lookIDs = (looks.data ?? []).map((l) => l.id as string);
  const [steps, members, photos] = await Promise.all([
    routineIDs.length > 0
      ? supabase.from("routine_steps").select("routine_id,user_item_id,position,note").in(
        "routine_id",
        routineIDs,
      )
      : Promise.resolve({ data: [], error: null }),
    collectionIDs.length > 0
      ? supabase.from("collection_items").select("collection_id").in("collection_id", collectionIDs)
      : Promise.resolve({ data: [], error: null }),
    lookIDs.length > 0
      ? supabase.from("look_photos").select("look_id").in("look_id", lookIDs)
      : Promise.resolve({ data: [], error: null }),
  ]);
  for (const r of [steps, members, photos]) {
    if (r.error) throw r.error;
  }
  const count = (rows: readonly Record<string, unknown>[] | null, key: string) => {
    const m = new Map<string, number>();
    for (const r of rows ?? []) {
      const k = r[key] as string;
      m.set(k, (m.get(k) ?? 0) + 1);
    }
    return m;
  };
  const memberN = count(members.data, "collection_id");
  const photoN = count(photos.data, "look_id");
  const p = (profile.data ?? {}) as Record<string, unknown>;
  const ctx: StylistContext = {
    profile: {
      skin_type: (p.skin_type as string | null) ?? null,
      concerns: (p.concerns as string[] | null) ?? [],
      hair_pattern: (p.hair_pattern as string | null) ?? null,
      domains: (p.domains as string[] | null) ?? [],
      climate: (p.climate as string | null) ?? null,
    },
    shelf: (shelf.data ?? []).map((s) => ({
      user_item_id: s.user_item_id as string,
      product_id: s.product_id as string,
      product_name: s.product_name as string,
      brand_name: s.brand_name as string,
      category_slug: s.category_slug as string,
      category_label: s.category_label as string,
      domain: s.domain as string,
      status: s.status as string,
      rank_position: (s.rank_position as number | null) ?? null,
      ranked_in_category: (s.ranked_in_category as number | null) ?? 0,
    })),
    routines: (routines.data ?? []).map((r) => ({
      id: r.id as string,
      title: r.title as string,
      slot: r.slot as string,
      steps: (steps.data ?? [])
        .filter((s) => s.routine_id === r.id)
        .sort((a, b) => (a.position as number) - (b.position as number))
        .map((s) => ({
          user_item_id: s.user_item_id as string,
          note: (s.note as string | null) ?? null,
        })),
    })),
    collections: (collections.data ?? []).map((c) => ({
      id: c.id as string,
      title: c.title as string,
      item_n: memberN.get(c.id as string) ?? 0,
    })),
    looks: (looks.data ?? []).map((l) => ({
      id: l.id as string,
      caption: (l.caption as string | null) ?? null,
      state: l.state as string,
      photo_n: photoN.get(l.id as string) ?? 0,
    })),
  };
  return { ctx, adult: isAdult((p.birth_year_month as string | null) ?? null, new Date()) };
}

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
      const { data, error } = await supabase.rpc("search_catalog", { q, p_domain: domain }).limit(
        8,
      );
      if (error) throw error;
      const hits: CatalogHit[] = (data ?? []).map((r: Record<string, unknown>) => ({
        id: r.id as string,
        name: r.name as string,
        brand_name: r.brand_name as string,
        category_slug: r.category_slug as string,
        domain: r.domain as string,
        n_face_offs: (r.n_face_offs as number | null) ?? null,
        catalog_image_key: (r.catalog_image_key as string | null) ?? null,
      }));
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
      const { data, error } = await supabase.rpc("affinity_for_user", { p_domain: null }).limit(8);
      if (error) throw error;
      const rows = (data ?? []) as Record<string, unknown>[];
      const text = rows.length === 0
        ? "no affinity yet — this person has not logged enough for a lean. say so."
        : rows.map((r) =>
          `${r.label} · n_signals=${r.n_signals} · score=${Number(r.shrunk_score).toFixed(2)}`
        ).join("\n");
      return { text, hits: [] };
    }
    case "crosswalk": {
      const { data, error } = await supabase.rpc("crosswalk_for_user", { p_limit: 6 });
      if (error) throw error;
      const rows = (data ?? []) as Record<string, unknown>[];
      const hits: CatalogHit[] = rows.map((r) => ({
        id: r.id as string,
        name: r.name as string,
        brand_name: r.brand_name as string,
        category_slug: r.category_slug as string,
        domain: r.domain as string,
        n_face_offs: (r.n_face_offs as number | null) ?? null,
        catalog_image_key: (r.catalog_image_key as string | null) ?? null,
      }));
      const text = rows.length === 0
        ? "no crosswalk — this person has no shade anchor yet, or too few people share it. say so."
        : rows.map((r) =>
          `product_id=${r.id} · ${r.brand_name} · ${r.name} · people who wear ${r.anchor_label} also wear this · n=${r.n}`
        ).join("\n");
      return { text, hits };
    }
    default:
      return { text: `unknown tool ${name}`, hits: [] };
  }
}

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

  const apiKey = env("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "the stylist is not configured here yet" }, 503);

  const supabase = createClient(env("SUPABASE_URL") ?? "", resolvePublishableKey(env), {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user } } = await supabase.auth.getUser(authorization.replace("Bearer ", ""));
  if (!user) return json({ error: "unauthenticated" }, 401);

  const started = Date.now();
  let ctx: StylistContext;
  let adult: boolean;
  try {
    ({ ctx, adult } = await prefetch(supabase, user.id));
  } catch {
    console.error("stylist prefetch failed", { user: user.id });
    return json({ error: "couldn't read your shelf just now" }, 502);
  }
  if (!adult) return json({ error: "not_yet", reason: "the stylist is for adults for now" }, 403);

  const anthropic = new Anthropic({ apiKey });
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
  const toolsUsed: string[] = [];
  const searched = new Map<string, CatalogHit>();
  let text = "";
  let calls = 0;

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
      text = response.content.filter((b): b is Anthropic.TextBlock => b.type === "text").map((b) =>
        b.text
      ).join("\n");
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
            console.error("stylist data tool failed", { user: user.id, tool: use.name });
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
        text = final.content.filter((b): b is Anthropic.TextBlock => b.type === "text").map((b) =>
          b.text
        ).join("\n");
        break;
      }
    }
  } catch (error) {
    // The SDK error can echo the request, and the request holds the person's
    // skin and shelf — so the class, never the message, and never the body.
    const kind = error instanceof Anthropic.RateLimitError
      ? "rate_limited"
      : error instanceof Anthropic.APIError
      ? `api_${error.status}`
      : "unknown";
    console.error("stylist turn failed", { user: user.id, kind, calls });
    return json({ error: "the stylist couldn't answer just now" }, 502);
  }

  const reply = assembleReply(text, blocks, chips, toolsUsed, [
    "profile",
    "shelf",
    "routines",
    "collections",
    "looks",
  ]);
  console.log("stylist turn", {
    user: user.id,
    tools: reply.tools_used,
    blocks: blocks.length,
    ms: Date.now() - started,
  });
  return json(reply, 200);
});
