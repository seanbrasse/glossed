# Session handoff — Aug 28 2026

Where Phase 1 stands, what to do next, and the decisions a new session would
otherwise have to rediscover. Read `docs/README.md` first for the design; this
file is only about state.

## 1. Where to start

Everything is tracked in **Linear**, not GitHub Issues:
workspace [glossed](https://linear.app/glossed), team **GLO**, project
**GLOSSED — Phase 1: The Journal**.

Next tickets, in dependency order:

| Ticket | Why it is next |
|---|---|
| [GLO-15](https://linear.app/glossed/issue/GLO-15) submission ladder | **In progress, 3 of 5 PRs merged.** Next: PR 4 (barcode + near-match rungs), PR 5 (create rung + confirm) |
| [GLO-16](https://linear.app/glossed/issue/GLO-16) shelf + cutouts | **Now unblocked** — GLO-48's presign merged in [#37](https://github.com/seanbrasse/glossed/pull/37) |
| [GLO-56](https://linear.app/glossed/issue/GLO-56) who owns the shade/size pick | A decision, not code. Blocks GLO-15 closing; read it before starting GLO-16 |
| [GLO-47](https://linear.app/glossed/issue/GLO-47) product page · [GLO-19](https://linear.app/glossed/issue/GLO-19) import | Parallel-safe — different feature directories, untouched |
| [GLO-14](https://linear.app/glossed/issue/GLO-14) catalog ingest | Server-only lane, parallel with all iOS work |
| [GLO-48](https://linear.app/glossed/issue/GLO-48) catalog images + R2 | Presign done. The rest **needs a human with the Cloudflare account** — see §9 |

**Blocked on a human, not on code:**
[GLO-50](https://linear.app/glossed/issue/GLO-50) App Store Connect — the Sign in
with Apple capability on the App ID gates [GLO-23](https://linear.app/glossed/issue/GLO-23)
(auth flows), which gates [GLO-18](https://linear.app/glossed/issue/GLO-18)
(onboarding). Everything else routes around it.

## 2. What exists

**34 PRs merged, all CI-green.** `main` is the only long-lived branch.

| Layer | State |
|---|---|
| Schema | 6 migrations, all applied to the hosted project. 49 pgTAP assertions. |
| `core/DataKit` | **FROZEN** — see §4. Config, client, typed errors, 4 repositories. 23 tests. |
| `core/DesignSystem` | Complete: tokens, 3 bundled fonts, 26 primitives. 11 tests. |
| `features/Ranking` | Complete: engine, rules, session, view. 29 tests. |
| `features/AddLadder` | Rungs, search rung, model, screen. 28 tests. Barcode + create rungs remain. |
| `supabase/functions` | `storage_presign` — scoped R2 PUT URLs. 14 Deno tests, run by the `functions · deno` CI job. **Not deployed** (§9). |
| Other features | Not started — the bulk of what remains. |

**Hosted Supabase**: project `glossed`, us-east-1. The project ref lives in the
Supabase dashboard and in `.env`, deliberately not written down here — RLS is
what actually protects the data, but a public repo is no place to hand someone
a target. Migrations are applied **manually via the Supabase MCP after each
merge**; [GLO-46](https://linear.app/glossed/issue/GLO-46) replaces that with a
CI `db push`. Never apply `seed.sql` to it — the seed creates fake auth users
and is local/staging only.

## 3. How this session worked (worth repeating)

- Branches `feat/GLO-<n>-desc`, conventional commits, squash merge.
- **PRs ≤5 files / 400 lines.** When one grew past that by acting on review
  findings, it used `size-override` **with a written reason as a PR comment** —
  the label is for that, not for convenience.
- Migrations are a global lock: one open migration PR at a time, and the merged
  SQL is applied to the hosted project before moving on.
- CI changes ship as their own small PR rather than riding along with feature
  work, so a gate is never quietly weakened inside an unrelated diff.
- **The user authorized self-merge on green CI for that session only.** The
  handbook default is a human read on every PR. Without explicit
  authorization, do not self-merge.

## 4. DataKit is frozen

`core/DataKit` is the one path every query takes. Do not modify it. If a feature
needs data it does not expose, that is a ticket against DataKit reviewed on its
own — not an edit made in passing. The reasoning is in `core/CLAUDE.md`; the
short version is that a missing session check there stops being a bug and
becomes a data leak.

Business rules do not belong in it either. Ranking order, wear-in gating and
unlock thresholds live in the features that own them.

## 5. The automated recap earns its keep — read it

Every PR opened gets a recap comment (mermaid diagram, file map by layer, schema
deltas, risk-ordered review notes) from `claude-code-action`, pinned to
**Sonnet 5** at 30 turns for cost.

It has now caught four real bugs, and they are all one family: **a name
claiming more certainty than the code can supply.** Two sub-shapes, worth
telling apart because the fixes differ.

*A guess reported as a statement.* A placement the system guessed recorded as
one the user stated — first for comparison-cap exhaustion, then, in the very fix
for the first, for skips, because a skip collapses the search range exactly as a
resolved comparison does. The fix adds a flag that admits the uncertainty.

*An attempt reported as an achievement.* `SearchRung` returned
`recordedMiss: true` after calling `recordFailedSearch` — which is `try?` inside
frozen DataKit and swallows its own transport errors, so the layer above cannot
know whether the miss was recorded. And `SearchRungModel` re-derived "is this a
miss" from the raw query while the rung decides from the *tidied* one, so `" a "`
would have claimed a miss for a search that never ran. The fix here *removes* a
claim rather than adding a flag — rename to what is actually known, or delete
the second implementation of the rule. Prefer this shape where it is available.

Treat its findings as review, not decoration: act on them before merging. If
acting on them pushes the PR past 400 lines, that is what `size-override` with a
written reason is for — trimming the reasoning the review asked for to hit a
number defeats the point of both.

Three mechanical facts:
- It **refuses to run on any PR that modifies workflow files** (a sound guard:
  otherwise a PR could rewrite the workflow to exfiltrate the key). Workflow
  changes cannot test themselves; the next feature PR is the check.
- It triggers only on `opened` / `reopened` / `ready_for_review`. A push does not
  retrigger it — close and reopen if you need a fresh one.
- **A green `recap` check does not prove a recap was posted.** Seen once on
  [#43](https://github.com/seanbrasse/glossed/pull/43): the agent spent its turns
  working out how to pipe a body into `gh pr comment`, left a stub comment, and
  exited green. Look for the comment, not the check mark; close and reopen to
  get a real one.

## 6. CI economics

The repo is **public**, so Actions minutes are free and this is now about speed
and noise rather than spend. The shape is still worth knowing: measured over 98
runs, the macOS iOS build was **87% of billed minutes**, because macOS bills at
**10×** and each run costs ~21 minutes.

Already in place: a concurrency group cancels superseded runs; a cheap Ubuntu
`scope` job gates the macOS build on Swift changes and the database suite on
`supabase/` changes; CI no longer re-runs on push to `main` (a squash-merge has
identical content to the PR just tested). Skipped jobs cost nothing.

If the repo ever goes private again, the macOS build is the only thing that
matters, and batching pushes is the single biggest lever.

## 7. Open threads

| Item | Where |
|---|---|
| Mid-session shelf changes desync a ranking session | [GLO-53](https://linear.app/glossed/issue/GLO-53) — decide with the screen that calls `apply` |
| Hair-type reference photos are placeholders | [GLO-52](https://linear.app/glossed/issue/GLO-52) — must be real, reviewed by people with those hair types |
| Category tree + chip vocabulary exist only in dev seeds | [GLO-51](https://linear.app/glossed/issue/GLO-51) — production needs them as a migration |
| No branch protection on `main` | Now that the repo is public, protection is free — worth enabling |
| Numbers chosen, not validated | `docs/BACKLOG.md` — payoff n≥8, min-n 5, shrinkage k≈10 |
| Nobody owns the shade/size pick | [GLO-56](https://linear.app/glossed/issue/GLO-56) — a search hit is a *product*, a shelf item is a *variant*. AddLadder or GLO-16's logging sheet? Blocks GLO-15 |
| Two-char search floor duplicated | [GLO-55](https://linear.app/glossed/issue/GLO-55) — frozen DataKit and AddLadder each hard-code it. Drift one way silently poisons the queue GLO-14 reads |
| Autocorrect fix lives at a call site | [GLO-57](https://linear.app/glossed/issue/GLO-57) — belongs in `GlossedInput`, next to `GlossedKeyboard`. Every future search field forgets it otherwise |
| Orphaned cutouts accumulate | [GLO-54](https://linear.app/glossed/issue/GLO-54) — re-shoots write new keys by design; nothing collects the old ones |

## 8. Local setup

```bash
make setup         # tools, xcodegen, supabase start, db reset + seed
make dev           # regenerate + open Xcode
supabase test db   # 49 pgTAP assertions
```

Docker runs via **colima** (`colima start --cpu 2 --memory 4`). One gotcha seen
this session: a Docker image whose layer was corrupted by a full disk keeps
being reused after a re-pull — `docker system prune -a -f --volumes` is the fix,
not another `docker pull`.

## 9. Blocked on a human, not on code

Both need credentials no agent has. Everything else routes around them.

**R2 provisioning ([GLO-48](https://linear.app/glossed/issue/GLO-48)).** Buckets
`glossed-prod` / `glossed-dev`, an API token, CORS, and a spend alert. Until
they exist, `storage_presign` is merged but deliberately **not deployed** — a
deployed function without secrets is just an endpoint that 500s. The env var
names are already in `.env.example` and are read only inside the Edge Function,
never in the app bundle. Deploy with `supabase functions deploy storage_presign`
once the secrets are set.

**App Store Connect ([GLO-50](https://linear.app/glossed/issue/GLO-50)).** The
Sign in with Apple capability on the App ID gates
[GLO-23](https://linear.app/glossed/issue/GLO-23) (auth), which gates
[GLO-18](https://linear.app/glossed/issue/GLO-18) (onboarding).

## 10. Two agents at once works, with one rule

Two sessions ran concurrently on Aug 28 without collision. What made it work:
**claim tickets explicitly before starting, by message, and say what you are
holding on disk but have not pushed.** Use `ListAgents` to find peers and
`SendMessage` to claim. The near-miss was both sessions eyeing GLO-15 at the
same minute; one message settled it.

Worth repeating: a session that is winding down should say so and name what it
is leaving free, and one agent should not merge another's PR when that PR
touches a file class its own instructions put off-limits — merging is not
modifying, but the conservative read costs nothing.

One git habit that cost the earlier session real work twice: `git push -q` hides
a failed push, and a docs commit whose content never reached the remote merged
as an empty pointer. **Check `git show --stat HEAD` before pushing**, and check
the PR's file list after.
