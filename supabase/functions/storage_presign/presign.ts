// Presign rules for user cutouts on R2 (ADR 0004, tech/01 §7).
//
// Kept separate from the handler so the parts worth getting wrong — the key
// shape and what the signature actually commits to — are testable without a
// running edge runtime or a live bucket.

import { AwsV4Signer } from "npm:aws4fetch@1.0.20";

/// A cutout is ~150KB (ADR 0004). Eight megabytes is generous for a HEIF
/// re-shoot and still small enough that a stolen URL cannot fill the bucket.
export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;

/// PNG and HEIF are what the on-device mask produces. Nothing else is a cutout.
export const ALLOWED_CONTENT_TYPES: Record<string, string> = {
  "image/png": "png",
  "image/heic": "heic",
};

/// Long enough to upload a cutout on a bad connection, short enough that a URL
/// leaked into a log is worthless by the time anyone reads it.
export const PRESIGN_TTL_SECONDS = 300;

export interface PresignInput {
  readonly userID: string;
  readonly userItemID: string;
  readonly contentType: string;
  readonly contentLength: number;
}

export interface R2Config {
  readonly accountID: string;
  readonly bucket: string;
  readonly accessKeyID: string;
  readonly secretAccessKey: string;
}

/// Why the request was rejected, in a form safe to hand back to the client.
export type Rejection = string;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function validate(input: Partial<PresignInput>): Rejection | null {
  if (!input.userItemID || !UUID.test(input.userItemID)) {
    return "user_item_id must be a uuid";
  }
  if (!input.contentType || !(input.contentType in ALLOWED_CONTENT_TYPES)) {
    return `content_type must be one of ${Object.keys(ALLOWED_CONTENT_TYPES).join(", ")}`;
  }
  if (
    typeof input.contentLength !== "number" ||
    !Number.isInteger(input.contentLength) ||
    input.contentLength <= 0
  ) {
    return "content_length must be a positive integer";
  }
  if (input.contentLength > MAX_UPLOAD_BYTES) {
    return `content_length exceeds ${MAX_UPLOAD_BYTES} bytes`;
  }
  return null;
}

/// `users/<uid>/items/<item_id>/<nonce>.<ext>`.
///
/// The user prefix is what a future bucket policy scopes on; the nonce is what
/// makes the key unguessable even to someone holding both ids, and it makes a
/// re-shoot a new object rather than an overwrite — the old cutout stays
/// cacheable until a sweep collects it.
export function cutoutKey(
  userID: string,
  userItemID: string,
  contentType: string,
  nonce: string = randomNonce(),
): string {
  const ext = ALLOWED_CONTENT_TYPES[contentType];
  return `users/${userID}/items/${userItemID}/${nonce}.${ext}`;
}

export function randomNonce(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/// A PUT URL that only accepts the exact upload we agreed to.
///
/// `allHeaders` is the load-bearing option: aws4fetch treats `content-type` and
/// `content-length` as unsignable by default, so without it the signature
/// commits to nothing but the host and the client may upload anything of any
/// size to the key.
export async function presignPut(
  config: R2Config,
  key: string,
  contentType: string,
  contentLength: number,
  ttlSeconds: number = PRESIGN_TTL_SECONDS,
): Promise<string> {
  const endpoint = `https://${config.accountID}.r2.cloudflarestorage.com`;
  const url = new URL(`${endpoint}/${config.bucket}/${key}`);
  url.searchParams.set("X-Amz-Expires", String(ttlSeconds));

  const signer = new AwsV4Signer({
    method: "PUT",
    url: url.toString(),
    headers: {
      "content-type": contentType,
      "content-length": String(contentLength),
    },
    accessKeyId: config.accessKeyID,
    secretAccessKey: config.secretAccessKey,
    service: "s3",
    region: "auto",
    signQuery: true,
    allHeaders: true,
  });

  const signed = await signer.sign();
  return signed.url.toString();
}
