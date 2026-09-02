// The service credential, wherever this stack keeps it. The modern env is a
// JSON dictionary (SUPABASE_SECRET_KEYS); the legacy single value still
// arrives on older stacks. Read either, prefer the modern.
//
// Shared because importing a function's index.ts would execute its
// Deno.serve — a module you import must not also be a server.
export function resolveSecretKey(env: (name: string) => string | undefined): string {
  const dict = env("SUPABASE_SECRET_KEYS");
  if (dict) {
    const parsed = JSON.parse(dict) as Record<string, string>;
    if (parsed.default) return parsed.default;
  }
  const legacy = env("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  throw new Error("no service credential in the environment");
}

/// The PUBLISHABLE key, for a client that runs as the CALLER: paired with the
/// request's own Authorization header it makes RLS the sandbox, so a read of
/// `user_shelf_items` cannot return anyone else's shelf whatever the request
/// asked for. Same resolution as storage_presign's copy — the platform injects
/// it under two names depending on the key scheme.
export function resolvePublishableKey(env: (name: string) => string | undefined): string {
  const legacy = env("SUPABASE_ANON_KEY");
  if (legacy) return legacy;
  const map = env("SUPABASE_PUBLISHABLE_KEYS");
  if (map) {
    const named = (JSON.parse(map) as Record<string, string>)["default"];
    if (named) return env(named) ?? named;
  }
  throw new Error("no publishable key in the function environment");
}
