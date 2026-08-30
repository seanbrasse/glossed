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
  lookKey,
  MAX_UPLOAD_BYTES,
  presignPut,
  r2Config,
  randomNonce,
  resolvePublishableKey,
  swatchKey,
  validate,
  validateLook,
  validateSwatch,
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

const OTHER_USER = "22222222-2222-4222-8222-222222222222";
const VARIANT = "33333333-3333-4333-8333-333333333333";

// ---------------------------------------------------------------------------
// Swatch keys (GLO-132, tech/02 §5).
//
// The property under test throughout: the storage layer knows nothing about
// `swatch_state`. A swatch sits in `pending_review` before it is public, and
// the object is reachable by anyone who can guess its path. So the key — not
// RLS — is what protects an unreviewed photo.
// ---------------------------------------------------------------------------

Deno.test("two swatches of the same variant by the same user get unrelated keys", () => {
  const a = swatchKey(USER, VARIANT, "image/png");
  const b = swatchKey(USER, VARIANT, "image/png");
  assert(a !== b, "a re-shoot must not overwrite, and must not be predictable from the first");
  // Unrelated, not merely different: everything before the nonce is shared, so
  // compare the nonces themselves rather than the whole path.
  const nonceOf = (k: string) => k.split("/").pop()!.split(".")[0];
  assert(nonceOf(a) !== nonceOf(b));
  assertEquals(nonceOf(a).length, 32);
});

Deno.test("a swatch key is not guessable from the ids alone", () => {
  // Someone holding both a user id and a variant id — both of which are visible
  // on a public product page — still cannot construct the path.
  const key = swatchKey(USER, VARIANT, "image/png");
  assert(key !== `users/${USER}/swatches/${VARIANT}/.png`);
  assert(/\/[0-9a-f]{32}\.png$/.test(key), "ends in a 128-bit random nonce");
});

Deno.test("swatches and cutouts occupy separate namespaces", () => {
  // Cutouts are disposable and key on the UserItem; swatches are user-posted
  // content and key on the Variant. A shared prefix would make a bucket
  // lifecycle rule impossible to write without parsing ids out of paths.
  const cutout = cutoutKey(USER, ITEM, "image/png");
  const swatch = swatchKey(USER, VARIANT, "image/png");
  assertStringIncludes(cutout, `users/${USER}/items/`);
  assertStringIncludes(swatch, `users/${USER}/swatches/`);
  assert(!swatch.startsWith(cutout.split("/").slice(0, 3).join("/") + "/items"));
});

Deno.test("the user prefix comes from the caller, so no payload can reach another namespace", () => {
  // The handler passes the JWT-derived user id here and never a request field.
  // This asserts the shape that makes that guarantee meaningful: the prefix is
  // this argument, so there is no second place for a user id to come from.
  const key = swatchKey(USER, VARIANT, "image/png");
  assert(key.startsWith(`users/${USER}/`));
  assert(!key.includes(OTHER_USER));
});

Deno.test("the extension follows the content type", () => {
  assert(swatchKey(USER, VARIANT, "image/png").endsWith(".png"));
  assert(swatchKey(USER, VARIANT, "image/heic").endsWith(".heic"));
});

Deno.test("a swatch needs a variant id, not a user_item id", () => {
  assertEquals(
    validateSwatch({ contentType: "image/png", contentLength: 1000 }),
    "variant_id must be a uuid",
  );
  assertEquals(
    validateSwatch({ variantID: "not-a-uuid", contentType: "image/png", contentLength: 1000 }),
    "variant_id must be a uuid",
  );
});

Deno.test("swatches inherit the cutout size and type limits rather than restating them", () => {
  const base = { variantID: VARIANT, contentType: "image/png" };
  assertEquals(validateSwatch({ ...base, contentLength: MAX_UPLOAD_BYTES }), null);
  assert(validateSwatch({ ...base, contentLength: MAX_UPLOAD_BYTES + 1 })!.includes("exceeds"));
  assert(validateSwatch({ ...base, contentLength: 0 })!.includes("positive integer"));
  assert(
    validateSwatch({ variantID: VARIANT, contentType: "image/gif", contentLength: 10 })!
      .includes("content_type"),
  );
});

Deno.test("a valid swatch request passes", () => {
  assertEquals(
    validateSwatch({ variantID: VARIANT, contentType: "image/heic", contentLength: 150_000 }),
    null,
  );
});

// --- the look namespace (GLO-198) ---

const lookInput = {
  lookID: "8b5aa841-3210-4bb1-9a70-3d5c0e1e2f11",
  position: 0,
  contentType: "image/jpeg",
  contentLength: 1024,
};

Deno.test("a well-formed look request passes", () => {
  assertEquals(validateLook(lookInput), null);
});

Deno.test("a look id must be a uuid and a position a non-negative integer", () => {
  assertEquals(validateLook({ ...lookInput, lookID: "nope" }), "look_id must be a uuid");
  assertEquals(
    validateLook({ ...lookInput, position: -1 }),
    "position must be a non-negative integer",
  );
  assertEquals(
    validateLook({ ...lookInput, position: 1.5 }),
    "position must be a non-negative integer",
  );
});

Deno.test("look keys are user-scoped, position-visible, and unguessable", () => {
  const key = lookKey("u1", lookInput.lookID, 2, "image/jpeg");
  assert(key.startsWith(`users/u1/looks/${lookInput.lookID}/2-`));
  assert(key.endsWith(".jpg"));
});

Deno.test("a re-shot look photo is a new object, never an overwrite", () => {
  const a = lookKey("u1", lookInput.lookID, 0, "image/jpeg");
  const b = lookKey("u1", lookInput.lookID, 0, "image/jpeg");
  assert(a !== b, "the nonce must differ — the row's r2_key moves, the orphan waits for the sweep");
});
