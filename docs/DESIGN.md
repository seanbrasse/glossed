# The design kit — where it is and how to open it

Six documents call the design kit the source of truth for screens. Until now
none of them said where it was, which is how `features/AddLadder` got built to
the design *system* (tokens, primitives) but not to the design *screens*. See
[GLO-62](https://linear.app/glossed/issue/GLO-62).

**If you are about to build a screen and cannot open the frame for it, stop and
say so.** Do not infer the layout from the primitives. The primitives constrain
how things look; they do not tell you what goes on the screen, in what order,
under what heading, or what the copy says — and all four of those are decided
already.

## The kit

Claude Design project **"Design system for GLOSSED"**:

<https://claude.ai/design/p/38230b94-09d2-4776-9d21-be0722ba54f2>

Deep-link a file with `?file=<path>`, URL-encoded:

| File | Link |
|---|---|
| Screen map (start here) | [`ui_kits/glossed-app/screen-map.html`](https://claude.ai/design/p/38230b94-09d2-4776-9d21-be0722ba54f2?file=ui_kits%2Fglossed-app%2Fscreen-map.html) |
| Screens | `ui_kits/glossed-app/screens.jsx` |
| Tokens | `ui_kits/glossed-app/tokens/` |

The screen map is the fastest way in: every V1 flow as a row of phone frames
with a caption under each explaining *why* it looks that way. The captions carry
intent the frames alone do not — read them.

### Opening it as an agent

`WebFetch` returns **403**. The page renders its content inside a
cross-origin iframe on `*.claudeusercontent.com`, and navigating to that origin
directly returns an empty document — it only renders inside its parent frame.

What works: the **browser pane**, reading visually.

```
preview_start   url: <the deep link above>
resize_window   preset: desktop      # the canvas renders too small at large viewports
computer        action: screenshot   # then scroll and screenshot
```

`get_page_text` and `javascript_tool` both come back empty on the **screen map**
for the same cross-origin reason, so that one is screenshots and scrolling.

### Reading the screens as source — do this instead

`screens.jsx` opens in a code viewer whose content lives in a `<textarea>` in
the **parent** document, which is same-origin and therefore readable. This is
far better than screenshots: exact copy, exact sizes, exact tokens, no squinting.

```
preview_start   url: https://claude.ai/design/p/38230b94-09d2-4776-9d21-be0722ba54f2?file=ui_kits%2Fglossed-app%2Fscreens.jsx
```

Then pull one screen by symbol — offsets shift whenever the kit is edited, so
search rather than hard-coding a number:

```js
(() => {
  const s = document.querySelector('textarea').value;
  const start = s.indexOf('G.Shelf = function');       // ← the screen you want
  const next  = s.indexOf('G.', start + 3);
  return s.slice(start, next);
})()
```

Results are truncated per call, so a long screen needs a couple of slices.

### The screens

`G.<name>` in `screens.jsx`. The screen map groups them into flows; this is the
inventory.

| Feature | Screens |
|---|---|
| Onboarding | `OnbHook` `OnbQuiz` `OnbPayoff` `OnbAccount` `OnbSignIn` `OnbBuild` `OnbTour` `OnbWelcome` `Phone` |
| Shelf | `Shelf` (bay view, list view, item sheet) |
| AddLadder | `AddLadder` (all five rungs in one component, switched on `rung`) |
| Import | `Import` |
| Discover | `Discover` `Leaderboard` `Tune` |
| ProductPage | `Product` |
| Ranking | `FaceOff` |
| Profile | `Profile` `Privacy` |
| Phase 2 | `Feed` |
| Shared | `Mock` — the product stand-in; `kind` is one of dropper/bottle/compact/tube/jar |

`G.Mock` is worth knowing about: the kit draws products as tinted vector shapes
by `kind`, not photographs. Until R2 has real images, that is closer to the
intended look than a typographic tile — and it is what the frames actually show.

## The other two source documents are not in the repo

| Document | Where | Reachable by a fresh session? |
|---|---|---|
| PRD v2.0 | `~/Downloads/glossed-prd-v2.0.md` | **No** — local to one machine |
| Greenfield Handbook | `~/Downloads/GREENFIELD_HANDBOOK_1.md` | **No** — same |

`docs/BACKLOG.md` already carries the action for the handbook ("fork into
`docs/HANDBOOK.md`"). The PRD has no such action and probably wants one: today
every claim sourced to it (`domain.md`, `tech/00` §2's "deltas that supersede
the PRD") is unverifiable by anyone who is not on that machine.

## The rule this file exists to make possible

A ticket that says "build screen X" should link the frame for X. A PR that
builds a screen should say which frame it was built to, and — where the two
differ — why. "It uses the right tokens" is not the same claim as "it matches
the design", and the second is the one the kit is for.
