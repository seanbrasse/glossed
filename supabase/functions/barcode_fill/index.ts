// barcode_fill — the transport half. A scanned code our catalog cannot name
// gets one chance at the Beauty API before the ladder falls through to
// near-matches (GLO-93).
//
// verify_jwt (platform default) already requires a valid caller. The API key
// is a function secret and never reaches the client — their docs are blunt
// that a leaked key is spendable quota.
//
// The response is a suggestion, not a row: {found, brand, name, domain, inci}.
// License posture (their FAQ, read Aug 2026): API data may be displayed to
// our users and cached inside the application while subscribed; we go one
// step shyer in this slice and persist nothing but the audit trail.
//
// Every upstream request — hit or 404 — bills one call, so every one writes
// an audit_records row, and the month's row count IS the budget gate. The
// Sandbox tier hard-caps at 100; we stop at 95 on our own count.

import { createClient } from "npm:@supabase/supabase-js@2";
import { resolveSecretKey } from "../_shared/credentials.ts";
import { budgetAllows, parseGTIN, toSuggestion } from "./lookup.ts";
import type { BeautyAPIProduct } from "./lookup.ts";

const BASE = Deno.env.get("BEAUTY_API_BASE") ?? "https://api.thebeautyapi.com";

const json = (body: unknown, status: number): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const apiKey = Deno.env.get("BEAUTY_API_KEY");
  if (!apiKey) {
    // No key configured is a deployment state, not a user error: the ladder
    // just proceeds as if the catalog missed, which it did.
    return json({ found: false, reason: "not_configured" }, 200);
  }

  let body: { gtin?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "body must be json" }, 400);
  }
  const gtin = parseGTIN(body.gtin ?? "");
  if (!gtin) return json({ error: "gtin must be 8-14 digits" }, 400);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const service = createClient(url, resolveSecretKey(Deno.env.get));

  // The budget gate: our own audit trail, this calendar month.
  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);
  const { count, error: countError } = await service
    .from("audit_records")
    .select("id", { count: "exact", head: true })
    .eq("actor", "barcode_fill")
    .gte("at", monthStart.toISOString());
  if (countError) {
    console.error("barcode_fill budget read failed", countError);
    return json({ found: false, reason: "budget_unreadable" }, 200);
  }
  if (!budgetAllows(count ?? 0)) {
    return json({ found: false, reason: "budget_exhausted" }, 200);
  }

  let upstreamStatus: number;
  let suggestion = { found: false } as ReturnType<typeof toSuggestion>;
  try {
    const upstream = await fetch(
      `${BASE}/v1/products/barcode/${encodeURIComponent(gtin)}`,
      { headers: { "x-api-key": apiKey } },
    );
    upstreamStatus = upstream.status;
    if (upstream.ok) {
      suggestion = toSuggestion(await upstream.json() as BeautyAPIProduct);
    }
  } catch (error) {
    console.error("barcode_fill upstream unreachable", error);
    return json({ found: false, reason: "upstream_unreachable" }, 200);
  }

  // Hit or 404, the call billed — the audit row is the meter. 4xx/5xx other
  // than 404 (403 wrong plan, 429 backoff) also billed conservatively: an
  // overcounting budget fails safe, an undercounting one fails at the cap.
  const { error: auditError } = await service.from("audit_records").insert({
    actor: "barcode_fill",
    action: "lookup",
    entity: "gtin",
    entity_id: gtin,
    after: { status: upstreamStatus, found: suggestion.found },
  });
  if (auditError) console.error("barcode_fill audit write failed", auditError);

  return json(suggestion, 200);
});
