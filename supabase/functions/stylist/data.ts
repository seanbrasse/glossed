// The Stylist's reads, every one under the caller's own JWT (RLS is the
// sandbox): the context prefetch, the rankable categories, and the cohort
// RPCs the planner and the model both draw on. No Deno.serve here — a module
// index.ts imports, never a server (_shared/credentials.ts's rule).

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { CategoryRef, DataRow, Domain, Fetch, FetchResult } from "./plan.ts";
import { type CatalogHit, isAdult, type StylistContext } from "./tools.ts";

export interface Prefetched {
  readonly ctx: StylistContext;
  readonly adult: boolean;
  readonly categories: readonly CategoryRef[];
  readonly hasShadeAnchor: boolean;
}

type Row = Record<string, unknown>;

export async function prefetch(supabase: SupabaseClient, userID: string): Promise<Prefetched> {
  const [profile, shelf, routines, collections, looks, categories, anchor] = await Promise.all([
    supabase.from("profiles")
      .select("skin_type,concerns,hair_pattern,domains,climate,birth_year_month")
      .eq("user_id", userID).maybeSingle(),
    supabase.from("user_shelf_items")
      .select(
        "user_item_id,product_id,product_name,brand_name,category_slug,category_label,domain,status,rank_position,ranked_in_category,benefit_line,catalog_image_key",
      )
      .eq("user_id", userID),
    supabase.from("routines").select("id,title,slot").eq("user_id", userID).is("deleted_at", null),
    supabase.from("collections").select("id,title").eq("user_id", userID).is("deleted_at", null),
    supabase.from("looks").select("id,caption,state").eq("user_id", userID),
    supabase.from("categories").select("id,slug,label,domain").is("parent_id", null),
    supabase.from("user_shade_anchor").select("variant_id").eq("user_id", userID).limit(1),
  ]);
  for (const r of [profile, shelf, routines, collections, looks, categories, anchor]) {
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
  const count = (rows: readonly Row[] | null, key: string) => {
    const m = new Map<string, number>();
    for (const r of rows ?? []) {
      const k = r[key] as string;
      m.set(k, (m.get(k) ?? 0) + 1);
    }
    return m;
  };
  const memberN = count(members.data, "collection_id");
  const photoN = count(photos.data, "look_id");
  const p = (profile.data ?? {}) as Row;
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
      benefit_line: (s.benefit_line as string | null) ?? null,
      catalog_image_key: (s.catalog_image_key as string | null) ?? null,
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
  return {
    ctx,
    adult: isAdult((p.birth_year_month as string | null) ?? null, new Date()),
    categories: (categories.data ?? []).map((c) => ({
      id: c.id as string,
      slug: c.slug as string,
      label: c.label as string,
      domain: c.domain as Domain,
    })),
    hasShadeAnchor: (anchor.data ?? []).length > 0,
  };
}

function hit(r: Row): CatalogHit {
  return {
    id: r.id as string,
    name: r.name as string,
    brand_name: r.brand_name as string,
    category_slug: r.category_slug as string,
    domain: r.domain as string,
    n_face_offs: (r.n_face_offs as number | null) ?? null,
    catalog_image_key: (r.catalog_image_key as string | null) ?? null,
  };
}

export async function searchCatalog(
  supabase: SupabaseClient,
  q: string,
  domain: string | null,
): Promise<CatalogHit[]> {
  const { data, error } = await supabase.rpc("search_catalog", { q, p_domain: domain }).limit(8);
  if (error) throw error;
  return ((data ?? []) as Row[]).map(hit);
}

export async function affinity(supabase: SupabaseClient): Promise<Row[]> {
  const { data, error } = await supabase.rpc("affinity_for_user", { p_domain: null }).limit(8);
  if (error) throw error;
  return (data ?? []) as Row[];
}

export async function crosswalk(supabase: SupabaseClient, limit: number): Promise<DataRow[]> {
  const { data, error } = await supabase.rpc("crosswalk_for_user", { p_limit: limit });
  if (error) throw error;
  return ((data ?? []) as Row[]).map((r) => ({
    ...hit(r),
    anchor_label: (r.anchor_label as string | null) ?? null,
    n: (r.n as number | null) ?? null,
  }));
}

export async function discover(supabase: SupabaseClient, limit: number): Promise<DataRow[]> {
  const { data, error } = await supabase.rpc("discover_for_user", { p_limit: limit });
  if (error) throw error;
  return ((data ?? []) as Row[]).map((r) => ({
    ...hit(r),
    basis: (r.basis as string | null) ?? null,
    basis_n: (r.basis_n as number | null) ?? null,
  }));
}

/// The leaderboard read (0042): rows below min-n come back with a null
/// claim and their n, which is the honest shape — the planner shows the n
/// and never ranks what the evidence cannot.
export async function leaderboard(
  supabase: SupabaseClient,
  categoryID: string,
  scope: "all" | "yours",
  limit: number,
): Promise<DataRow[]> {
  const { data, error } = await supabase.rpc("leaderboard", {
    p_category: categoryID,
    p_scope: scope,
    p_ascending: false,
    p_limit: limit,
  });
  if (error) throw error;
  return ((data ?? []) as Row[]).map((r) => ({
    ...hit(r),
    n_users: (r.n_users as number | null) ?? null,
    mean_percentile: (r.mean_percentile as number | null) ?? null,
  }));
}

/// Runs what a plan asked for, in parallel. A read that fails yields no
/// rows rather than failing the turn — the planner says "no receipts yet"
/// and the log carries the tool name, never the rows.
export function runFetches(
  supabase: SupabaseClient,
  fetches: readonly Fetch[],
  userID: string,
): Promise<FetchResult[]> {
  return Promise.all(fetches.map(async (fetch): Promise<FetchResult> => {
    try {
      switch (fetch.kind) {
        case "leaderboard":
          return {
            fetch,
            rows: await leaderboard(supabase, fetch.category.id, fetch.scope, fetch.limit),
          };
        case "discover":
          return { fetch, rows: await discover(supabase, fetch.limit) };
        case "crosswalk":
          return { fetch, rows: await crosswalk(supabase, fetch.limit) };
      }
    } catch {
      console.error("stylist fetch failed", { user: userID, fetch: fetch.kind });
      return { fetch, rows: [] };
    }
  }));
}
