// track_ingest — the pure half: what counts as an acceptable event batch.
//
// The client's compiler-checked enum is the first wall; this is the second,
// for anything that is not our client. The rules mirror tech/06 §3 and are
// deliberately shape rules, not a name whitelist: the registry lives in one
// place (core/Tracking), and duplicating it here would give the two lists a
// way to disagree. A well-shaped unknown name lands and shows up in rollups,
// where an event nobody recognises is a question — not a silent drop.

export interface IncomingEvent {
  id: string;
  name: string;
  ts: number;
  props?: Record<string, unknown>;
  screen?: string;
  anon_id?: string;
}

export const MAX_BATCH = 100;
export const MAX_PROPS = 20;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const NAME = /^[a-z0-9]+(_[a-z0-9]+)*$/;
const KEY = NAME;

/** Why one event is unacceptable, or null. */
export function reject(event: IncomingEvent, now: number): string | null {
  if (!UUID.test(event.id ?? "")) return "id must be a lowercase uuid";
  if (!NAME.test(event.name ?? "")) return "name must be object_action snake case";
  if (typeof event.ts !== "number" || !Number.isFinite(event.ts)) return "ts must be epoch seconds";
  // A day of clock skew forward, a year back — outside that the event is
  // garbage or a replay, and either way not analytics.
  if (event.ts > now + 86_400 || event.ts < now - 31_536_000) return "ts out of range";
  if (event.screen !== undefined && typeof event.screen !== "string") {
    return "screen must be a string";
  }
  if (event.anon_id !== undefined && !UUID.test(event.anon_id)) return "anon_id must be a uuid";

  const props = event.props ?? {};
  const entries = Object.entries(props);
  if (entries.length > MAX_PROPS) return "too many props";
  for (const [key, value] of entries) {
    if (!KEY.test(key)) return `prop key ${key} is not snake case`;
    const kind = typeof value;
    // Identifiers, not values: scalars only. An object or array prop is the
    // shape a note, a photo reference, or a body-fact blob would arrive in.
    if (kind !== "string" && kind !== "number" && kind !== "boolean") {
      return `prop ${key} must be a scalar`;
    }
    if (kind === "string" && (value as string).length > 200) {
      return `prop ${key} is too long to be an identifier`;
    }
  }
  return null;
}

/** Splits a batch into what lands and what does not, with reasons. A batch is
 * never all-or-nothing: one malformed event must not cost the other 99. */
export function partition(
  batch: IncomingEvent[],
  now: number,
): { accepted: IncomingEvent[]; rejected: { index: number; reason: string }[] } {
  const accepted: IncomingEvent[] = [];
  const rejected: { index: number; reason: string }[] = [];
  batch.forEach((event, index) => {
    const reason = reject(event, now);
    if (reason) {
      rejected.push({ index, reason });
    } else {
      accepted.push(event);
    }
  });
  return { accepted, rejected };
}
