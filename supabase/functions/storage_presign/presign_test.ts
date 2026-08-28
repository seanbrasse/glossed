import {
  assert,
  assertEquals,
  assertMatch,
  assertStringIncludes,
  assertThrows,
} from "jsr:@std/assert@1";
import {
  ALLOWED_CONTENT_TYPES,
  cutoutKey,
  MAX_UPLOAD_BYTES,
  presignPut,
  r2Config,
  randomNonce,
  resolvePublishableKey,
  validate,
} from "./presign.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const ITEM = "22222222-2222-4222-8222-222222222222";

const config = {
  accountID: "acct",
  bucket: "glossed-dev",
  accessKeyID: "AKIAEXAMPLE",
  secretAccessKey: "secret",
};

const valid = { userItemID: ITEM, contentType: "image/png", contentLength: 1024 };

Deno.test("a well-formed request passes", () => {
  assertEquals(validate(valid), null);
});

Deno.test("a non-uuid item id is rejected before anything is signed", () => {
  assertEquals(validate({ ...valid, userItemID: "../../etc" }), "user_item_id must be a uuid");
});

Deno.test("only cutout content types are allowed", () => {
  assert(validate({ ...valid, contentType: "image/svg+xml" }));
  assert(validate({ ...valid, contentType: "text/html" }));
  for (const type of Object.keys(ALLOWED_CONTENT_TYPES)) {
    assertEquals(validate({ ...valid, contentType: type }), null);
  }
});

Deno.test("content length must be a positive integer within the cap", () => {
  assert(validate({ ...valid, contentLength: 0 }));
  assert(validate({ ...valid, contentLength: -1 }));
  assert(validate({ ...valid, contentLength: 1.5 }));
  assert(validate({ ...valid, contentLength: MAX_UPLOAD_BYTES + 1 }));
  assertEquals(validate({ ...valid, contentLength: MAX_UPLOAD_BYTES }), null);
});

Deno.test("the key is scoped to the user and carries an unguessable nonce", () => {
  const key = cutoutKey(USER, ITEM, "image/png");
  assertMatch(key, new RegExp(`^users/${USER}/items/${ITEM}/[0-9a-f]{32}\\.png$`));
});

Deno.test("a re-shoot never overwrites the previous cutout", () => {
  const first = cutoutKey(USER, ITEM, "image/png");
  const second = cutoutKey(USER, ITEM, "image/png");
  assert(first !== second);
});

Deno.test("nonces do not repeat", () => {
  const seen = new Set(Array.from({ length: 500 }, () => randomNonce()));
  assertEquals(seen.size, 500);
});

Deno.test("the signature commits to the content type and the byte count", async () => {
  const key = cutoutKey(USER, ITEM, "image/png");
  const url = await presignPut(config, key, "image/png", 1024);
  const signedHeaders = new URL(url).searchParams.get("X-Amz-SignedHeaders");
  // Without allHeaders, aws4fetch drops both of these and signs only the host —
  // which would let a stolen URL upload anything of any size.
  assertEquals(signedHeaders, "content-length;content-type;host");
});

Deno.test("changing the byte count changes the signature", async () => {
  const key = cutoutKey(USER, ITEM, "image/png");
  const [a, b] = await Promise.all([
    presignPut(config, key, "image/png", 1024),
    presignPut(config, key, "image/png", 1025),
  ]);
  const sig = (u: string) => new URL(u).searchParams.get("X-Amz-Signature");
  assert(sig(a) !== sig(b));
});

Deno.test("the url points at the bucket and expires", async () => {
  const key = cutoutKey(USER, ITEM, "image/heic");
  const url = await presignPut(config, key, "image/heic", 2048, 300);
  assertStringIncludes(url, "https://acct.r2.cloudflarestorage.com/glossed-dev/");
  assertEquals(new URL(url).searchParams.get("X-Amz-Expires"), "300");
  assert(new URL(url).searchParams.get("X-Amz-Signature"));
});

const envFrom = (vars: Record<string, string>) => (name: string) => vars[name];

Deno.test("the legacy publishable key is used when the platform sets it", () => {
  assertEquals(
    resolvePublishableKey(envFrom({ SUPABASE_ANON_KEY: "sb_publishable_legacy" })),
    "sb_publishable_legacy",
  );
});

Deno.test("the new key map resolves through the env var it names", () => {
  // SUPABASE_PUBLISHABLE_KEYS maps a role to the *name* of the var holding the
  // key, not to the key — reading it as the key itself is the mistake here.
  const env = envFrom({
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({ default: "SB_PUBLISHABLE_DEFAULT" }),
    SB_PUBLISHABLE_DEFAULT: "sb_publishable_new",
  });
  assertEquals(resolvePublishableKey(env), "sb_publishable_new");
});

Deno.test("an empty environment fails loudly rather than building a keyless client", () => {
  assertThrows(() => resolvePublishableKey(envFrom({})));
  assertThrows(() => resolvePublishableKey(envFrom({ SUPABASE_PUBLISHABLE_KEYS: "{}" })));
});

Deno.test("every R2 credential is required", () => {
  const full = {
    R2_ACCOUNT_ID: "acct",
    R2_BUCKET: "glossed-dev",
    R2_ACCESS_KEY_ID: "AKIAEXAMPLE",
    R2_SECRET_ACCESS_KEY: "secret",
  };
  assertEquals(r2Config(envFrom(full)).bucket, "glossed-dev");
  for (const missing of Object.keys(full)) {
    const partial = { ...full } as Record<string, string>;
    delete partial[missing];
    assertThrows(() => r2Config(envFrom(partial)), Error, "R2 credentials missing");
  }
});
