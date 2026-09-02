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
- **Spend**: the shaped asks cost no model call at all (§4). The free-form
  fallback runs `claude-sonnet-5` at `effort: "low"` — the Sept 2 bake-off
  (`scripts/stylist_bakeoff.ts`: nine open questions, maya's context, three
  models): Sonnet 5 answered every one on the beauty half with its receipts
  at ~0.3–1.4¢ and 3–12 s a turn, a third of Opus 5's cost (0.8–3.8¢, 5–19 s)
  and half its latency; Haiku 4.5 (~0.7¢, 2–4 s) refused a layering question
  as "a dermatologist question", asked for facts already in `<context>`,
  invented a cleanser's strength and never reached for a tool. `STYLIST_MODEL`
  in the env switches without a deploy. Per-turn caps (`MAX_TOOL_CALLS`,
  `max_tokens`, transcript trimmed to the last 12 messages), the frozen system
  prompt + context block cached. A per-user daily budget needs a table —
  follow-up, with the flag.
- **Behind a flag.** `StylistFlag` (DEBUG builds on; release off until Sean
  flips it). The tab does not render when the flag is off.

## 4. Architecture

*Revised Sept 2 (Sean: "as little AI as possible — searching, filtering,
looking at data and making comparisons"). The model is the fallback, not the
engine.*

```
app · features/Stylist ──POST /functions/v1/stylist (JWT)──▶ Edge Function `stylist`
   transcript (text only)                                     │ 1. auth.getUser
   ◀── {text, blocks, chips, grounded_in} ───────────────────  │ 2. prefetch under the caller's JWT (data.ts)
                                                              │    profile · shelf (+benefit_line) · routines ·
                                                              │    collections · looks · categories · shade anchor
                                                              │ 3. plan.ts — rules, no model:
                                                              │      intent from the words via lexicon.ts (medical first)
                                                              │      look      = makeup from the shelf + own looks as doors
                                                              │      routine   = shelf in category order, one gap
                                                              │      missing   = concern's wants − shelf → leaderboard
                                                              │      try next  = discover + crosswalk, merged, with n
                                                              │      compare   = own ranks in a category
                                                              │      about     = the catalog's line + the rank
                                                              │ 4. only `open` (no rule matched) AND a key → model.ts
                                                              │      Sonnet 5 tool loop (STYLIST_MODEL), ids validated
                                                              └ 5. one JSON reply; nothing stored
```

- **The words are learned offline, matched at zero tokens.** `lexicon.ts`
  is how people actually ask — slang ("slay", "grwm", "full beat"),
  occasions ("date night", "wedding guest"), category synonyms ("spf",
  "curl cream", "skin tint"), slot and domain cues, the medical list —
  written by a Claude Code session from how beauty is talked about on the
  internet, never by a model at runtime. `lexicon_test.ts` is the simulated
  corpus (60 phrasings, each with the intent it must land on); a real
  phrasing that misses is a row for the lexicon, then a row for the corpus.
  A rule hit answers in ~300 ms; only the leftover reaches the model.
- **The model hands shaped work back to the rules.** Sonnet sees the plans
  as tools (`build_routine`, `find_gaps`, `what_to_try`, `compare_owned`,
  `look_for_tonight`): for a creative phrasing the lexicon missed, it
  interprets once in a few output tokens and the planner answers with every
  n and the cards — the model adds a line, never a fact. A Haiku-then-Sonnet
  router was considered and rejected (Sept 2): it adds a hop to every open
  turn, puts the least reliable model on the routing decision, and a misroute
  by rules is harmless (the model still answers) while a misroute by a
  classifier is a confidently wrong card.
- **Rules first.** `plan.ts` is pure and tested: it reads the words and the
  context, names the fetches it wants (`leaderboard`, `discover_for_user`,
  `crosswalk_for_user`) and finishes from their rows with templated copy.
  A routine, a gap list, a comparison and a "try next" cost **zero model
  calls**. `tools_used` says which path answered (`plan_routine`,
  `leaderboard`, … or `model`), so the analytics event can count it.
- **Cohorts are the app's, not the model's.** `leaderboard(p_scope = 'yours')`
  resolves the caller's cohort server-side (shade anchor for makeup, hair
  pattern for haircare) and falls back to everyone silently — so the planner
  decides the *label* from what it knows (`cohortScope`) and every product row
  carries `basis_label` + `basis_n`: *"face-offs by people with 3b hair · 12"*.
  The app renders that through `EvidenceLine`; a zero-n basis ("a wander, no
  evidence") is shown as its words, never a count.
- **Without a key the stylist still works.** A free-form question gets the
  honest menu (`OPEN_WITHOUT_MODEL`), not a 503. With a key, only that
  question reaches `model.ts`, which keeps the original loop: prefetch as
  cached system text, eight tools, ids validated, `MAX_TOOL_CALLS`.
- **Turn-at-a-time, no streaming.** Streaming needs a third method on
  `GlossedClient` (frozen core). `invokeEdgeFunctionForData` is the zero-opening
  path; a "thinking…" state covers the wait.
- **Saving a routine** goes through the existing `RoutinesRepository.saveDraft`
  (title, slot, steps with notes). The save mints the id; the card keeps it and
  offers *open it* — the shell's `openOwnItem = .routine(id)`, the same detail
  → edit door the profile uses — and tells the shell (`onRoutineSaved`) so the
  profile reloads in place (GLO-278's trip, from a tab instead of a cover).
  Cadence is not in `RoutineDraft` yet — the card says the slot only.
- **Opening a look or collection** uses the shell's existing doors
  (`openLook`, `openOwnItem`) — the app owns every crossing, features never
  import features.
- The function's pure halves (`tools.ts`, `plan.ts`) are unit-tested with
  `deno test`; `data.ts`, `model.ts` and `index.ts` are not imported by tests,
  per `_shared/credentials.ts`.
- **Not yet in the rules:** ingredient clashes (no INCI table — the stylist
  says so), fit-based foundation picks (use case 11), repurchase (12). Each
  is a planner intent when its data exists.

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
