import { assert, assertEquals } from "jsr:@std/assert@1";
import { type IncomingEvent, MAX_PROPS, partition, reject } from "./validate.ts";

const NOW = 1_790_000_000;

const good: IncomingEvent = {
  id: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
  name: "item_logged",
  ts: NOW - 10,
  props: {
    variant_id: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
    source: "barcode",
    week: 3,
    hit: true,
  },
  screen: "shelf",
};

Deno.test("a well-shaped event passes", () => {
  assertEquals(reject(good, NOW), null);
});

Deno.test("names outside object_action snake case are refused", () => {
  assert(reject({ ...good, name: "ItemLogged" }, NOW));
  assert(reject({ ...good, name: "item logged" }, NOW));
  assert(reject({ ...good, name: "" }, NOW));
});

Deno.test("an event id must be a uuid — it is the retry-dedupe key", () => {
  assert(reject({ ...good, id: "42" }, NOW));
});

Deno.test("props are scalars only — the shape a note or a blob cannot take", () => {
  assert(reject({ ...good, props: { nested: { a: 1 } } }, NOW));
  assert(reject({ ...good, props: { list: [1, 2] } }, NOW));
  assert(
    reject({ ...good, props: { essay: "x".repeat(300) } }, NOW),
    "a 300-char string is not an identifier",
  );
});

Deno.test("clock skew is tolerated a day forward, a year back — no further", () => {
  assertEquals(reject({ ...good, ts: NOW + 3600 }, NOW), null);
  assert(reject({ ...good, ts: NOW + 172_800 }, NOW));
  assert(reject({ ...good, ts: NOW - 40_000_000 }, NOW));
});

Deno.test("a prop budget bounds the payload", () => {
  const wide = Object.fromEntries(
    Array.from({ length: MAX_PROPS + 1 }, (_, i) => [`k${i}`, i]),
  );
  assert(reject({ ...good, props: wide }, NOW));
});

Deno.test("one malformed event does not cost the rest of the batch", () => {
  const { accepted, rejected } = partition(
    [good, { ...good, name: "BAD NAME" }, { ...good, id: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeef" }],
    NOW,
  );
  assertEquals(accepted.length, 2);
  assertEquals(rejected.length, 1);
  assertEquals(rejected[0].index, 1);
});
