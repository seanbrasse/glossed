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
