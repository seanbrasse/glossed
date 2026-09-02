# 08 · The Stylist — build-ready spec (Phase 2 §7, pulled forward)

*Sept 1 2026. Sean's direction, verbatim: "a discover tab that goes between the
nav and shelf. A personal stylist type chat that can answer beauty / skincare /
haircare related questions, as well as recommend things based on the user's skin
data and data we have on the user's own products … keep the agent's responses
narrow to our topic … suggest a routine for the user based on their products and
what they're targeting (with a UI of the routine in the chat), and the ability
to save the routine … reference the user's own looks, collections, also showing
them as a UI that the user can click on … human in the loop suggestion chips …
above the input."*

This is `tech/03` §7 ("The Stylist — a discovery feature wearing a chat costume")
made buildable now. Where this file and §7 disagree, this file is newer; the
rules §7 states are kept, not relaxed. Two rulings this direction makes on
Sean's behalf, stated so they are visible: **the nav gains a fourth tab**
(discover · stylist · shelf · you · plus — the question `tech/00` delta 11
parked is answered by the ask itself), and **the Stylist ships in Phase 1**,
behind a flag.

## 1. What it is, in one paragraph

A chat that knows your shelf. It reads what the app already knows — fit
answers, skin type and concerns, hair pattern, what you own and how you ranked
it, your routines, collections and looks — plus the catalog and its cohort
receipts, and answers beauty questions in that light. Its best answers are not
paragraphs: a routine built from your products, a short list of products with
their n, your own look or collection handed back as a card you can open. It
never diagnoses, never coerces a purchase, and says once and kindly when a
question is outside what it does.

## 2. Use cases (what a turn can be)

| # | the user says | the stylist does | the reply carries |
|---|---|---|---|
| 1 | "build me a morning routine from what I own" | reads the shelf + concerns, orders steps, names the one gap | **routine card** (steps from real `user_items`, a gap step if a category is missing) + save |
| 2 | "my skin's tight after cleansing" | reads skin type/concerns + the cleanser on the shelf; caution-not-verdict | text + a **routine card** or a product row, never a diagnosis |
| 3 | "what am I missing for dryness / acne / …" | set difference: categories the concern usually wants vs what the shelf holds | text + **product list** from `search_catalog`, each with its n |
| 4 | "do my products clash / can I use X with Y" | ingredient caution from INCI where we have it; phrased as caution | text; a **product list** of the two items; no verdicts |
| 5 | "compare my two serums" | shelf rows + rank position + chips | text with the ranks and chip receipts; product rows |
| 6 | "what should I try next" | affinity + crosswalk + want-to-try gaps | **product list** with n, "people who wear X also wear Y" |
| 7 | "recreate my golden hour look tonight" | reads the look's tagged products, suggests swaps from the shelf | **look card** (opens the post) + text |
| 8 | "put together a travel kit / a collection for …" | picks from the shelf | **collection draft** → saved as a collection (follow-up: needs a create path) |
| 9 | "what does niacinamide do for me" | beauty knowledge, tied to the user's shelf item if they own one | text + the product row if owned |
| 10 | "how often should I use my exfoliant" | frequency guidance as caution; ties to the routine's cadence | text; offers a routine edit (follow-up: edit path) |
| 11 | "which of my foundations fits me best" | anchors + fit answers | text with the fit receipts; product rows |
| 12 | "is this worth repurchasing" | the item's rank, chips, status history | text + product row; never "buy" — "keep / finish / not for you" |
| 13 | off-topic ("what's the capital of…") | one-line redirect, offers a beauty next step | text + chips |
| 14 | anything medical (rash, infection, prescription) | declines to diagnose, suggests a dermatologist, stays on the beauty half | text |

Chips are the human-in-the-loop layer: every reply proposes up to three next
steps ("build my pm routine", "show the 3 that fit", "not now"); tapping one
sends its text as the user's message. **Nothing acts without a tap** — a routine
is not saved, a product is not added to want-to-try, until the user does it.

## 3. Hard rules (inherited, not new)

- **Grounded by construction.** The server prefetches the user's context
  (profile facts, shelf rows with rank + chips, routines, collections, looks)
  under the caller's own JWT and hands it to the model as data. Every answer is
  therefore "using our data"; the reply reports `grounded_in` (which context
  and tools fed it), and the app renders a claim only when it has its n.
- **Structured artifacts, not paragraphs**, wherever the answer has a shape:
  `routine_draft`, `product_list`, `look_ref`, `collection_ref`, `chips`.
  Artifacts reference **only ids the server fetched or searched this turn** —
  the server validates every id and drops what it cannot vouch for.
- **Narrow.** Skin, hair, makeup, fragrance, and what is on the shelf. The
  system prompt says so; the redirect is one line and offers a next step.
- **Never medical.** No diagnosis, no dosing, no "this will cure". Ingredient
  talk is caution, not verdict; comedogenicity is never surfaced. A response
  classifier for medical claims is the follow-up ticket; v1 is prompt + refusal
  patterns + the redirect.
- **Never coerce.** "Keep / finish / not for you", "people who wear X also wear
  Y · n = 12" — never "buy", never "your match", never a persona.
- **Regulated data**: body facts go to the Claude API as request data (the
  spec's tool results, made explicit) and nowhere else — **never logged**,
  never in analytics props (`stylist_query` carries `tools_used` and
  `answered` only), never persisted by the stylist. **No transcript table**:
  the thread lives in the app's memory for the tab's life. Persisting history
  is a `domain.md` §6 retention decision, not a default.
- **Minors (13–17)**: no ruling exists. v1 shows the tab only to adults
  (`is_minor_user` false); the tab reads *"not yet"* for a minor. Sean decides.
- **Spend**: per-turn caps (`MAX_TOOL_CALLS`, `max_tokens`, transcript
  trimmed to the last 12 messages), `effort: "low"` on `claude-opus-5`, the
  frozen system prompt + context block cached. A per-user daily budget needs a
  table — follow-up, with the flag.
- **Behind a flag.** `StylistFlag` (DEBUG builds on; release off until Sean
  flips it). The tab does not render when the flag is off.

## 4. Architecture

```
app · features/Stylist ──POST /functions/v1/stylist (JWT)──▶ Edge Function `stylist`
   transcript (text only)                                     │ 1. auth.getUser
   ◀── {text, blocks, chips, grounded_in} ───────────────────  │ 2. prefetch context under the caller's JWT
                                                              │    (RLS is the sandbox — user_shelf_items, routines, …)
                                                              │ 3. claude-opus-5, tools:
                                                              │      search_catalog · query_affinity · crosswalk
                                                              │      propose_routine · show_products · reference_look
                                                              │      reference_collection · suggest_chips
                                                              │ 4. artifact tools validate ids against the prefetch
                                                              └ 5. one JSON reply; nothing stored
```

- **Turn-at-a-time, no streaming.** Streaming needs a third method on
  `GlossedClient` (frozen core). `invokeEdgeFunctionForData` is the zero-opening
  path; a "thinking…" state covers the wait. Streaming is a follow-up with a
  DataKit opening.
- **Saving a routine** goes through the existing `RoutinesRepository.saveDraft`
  (title, slot, steps with notes). Cadence is not in `RoutineDraft` yet —
  the stylist's card says the slot only.
- **Opening a look or collection** uses the shell's existing doors
  (`openLook`, `openOwnItem`) — the app owns every crossing, features never
  import features.
- The function's pure half (`tools.ts`: prompt, tool schemas, context
  rendering, artifact validation, caps) is unit-tested with `deno test`; the
  transport half (`index.ts`) is not imported by tests, per `_shared/credentials.ts`.

## 5. Tickets (the workspace is at its issue cap — tracked as a comment thread on GLO-224 until it is lifted)

| # | ticket | files | needs |
|---|---|---|---|
| STY-1 | this spec | `docs/tech/08-stylist.md` | — |
| STY-2 | edge function `stylist`: prefetch, tool loop, artifacts, caps, tests | `supabase/functions/stylist/{tools.ts,tools_test.ts,index.ts}`, `_shared/credentials.ts` | `ANTHROPIC_API_KEY` in `supabase/functions/.env` and on hosted (Sean) |
| STY-3 | nav glyph | `core/DesignSystem/…/KitIcons.swift`, `FloatingNav.swift` | — |
| STY-4 | `features/Stylist`: store, model, wire types, thread + cards + chips + composer, tests | `features/Stylist/**` | — |
| STY-5 | app wiring: fourth tab behind `StylistFlag`, live store, routine save, look/collection doors | `project.yml`, `app/…/AppShell.swift`, `AppShellTabs.swift`, `AppShellStylist.swift` | — |
| STY-6 | `stylist_query` analytics event (`tools_used`, `answered`) | `core/Tracking` or feature | — |
| STY-7 | medical-claim response classifier (second pass) | function | Sean's ruling on refusal copy |
| STY-8 | per-user daily budget | migration **0058+** | migration slot |
| STY-9 | minors ruling | docs | Sean |
| STY-10 | `G.Stylist` frame in the kit | `screens.jsx`, `screen-map.html` | `/design-login` (interactive) — the canvas for now: the Stylist Tab artifact |
| STY-11 | streaming replies | `GlossedClient` | DataKit opening |
| STY-12 | collection draft → create; routine edit path (set semantics) | DataKit | DataKit opening |

Done for STY-2 looks like: `make functions-test` green, and `curl` against the
local function with maya's JWT returns a routine card built only from her
`user_items`. Done for STY-5 looks like: the tab renders behind the flag, a
routine proposed in the chat is on the profile after *save*, and a look card
opens the post.
