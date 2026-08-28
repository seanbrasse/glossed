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

Two routes work, and the second one is the one to use.

**Looking at it.** The **browser pane**, reading visually — for the rendered
frames, which is what the screen map is for.

```
preview_start   url: <the deep link above>
resize_window   preset: desktop      # the canvas renders too small at large viewports
computer        action: screenshot   # then scroll and screenshot
```

The frames themselves are drawn inside the cross-origin iframe, so that part is
screenshots and scrolling — `get_page_text` and `javascript_tool` see the
surrounding page, not the canvas.

### Reading the files as source — do this instead

Ask the project's own API for the file. It returns the bytes, exactly: exact
copy, exact sizes, exact tokens, no squinting and no scrolling.

Open any page of the project in the browser pane first — the call is
same-origin and rides the session's cookies.

```
preview_start   url: https://claude.ai/design/p/38230b94-09d2-4776-9d21-be0722ba54f2
```

Then, in `javascript_tool`:

```js
(async () => {
  const r = await fetch('/design/anthropic.omelette.api.v1alpha.OmeletteService/GetFile', {
    method: 'POST', credentials: 'include',
    headers: {'content-type': 'application/json'},
    body: JSON.stringify({projectId: '38230b94-09d2-4776-9d21-be0722ba54f2',
                          path: 'ui_kits/glossed-app/screens.jsx'})});
  const {content} = await r.json();                     // base64
  window.__SRC = new TextDecoder().decode(Uint8Array.from(atob(content), c => c.charCodeAt(0)));
  return window.__SRC.length;                           // ~108,000
})()
```

`ListFiles` takes the same `{projectId, path}` and lists a directory, so the
whole kit is walkable — `tokens/colors.css`, `components/glossed-lib.js` (where
the shared components live), `ui_kits/glossed-app/screen-map.html`.

Stash the source on `window` as above, then pull one screen by symbol. Offsets
shift whenever the kit is edited, so search rather than hard-coding a number:

```js
(() => {
  const s = window.__SRC;
  const start = s.indexOf('G.Shelf = function');       // ← the screen you want
  const next  = s.indexOf('G.', start + 3);
  return s.slice(start, next);
})()
```

Results are truncated per call, so a long screen needs a couple of slices —
`s.slice(start, start + 3500)`, then continue from there.

**Read `screen-map.html` too, not just `screens.jsx`.** The frames say what a
screen looks like; the map's `note=` captions say why, and they are the half a
`.jsx` file cannot carry. Fetch it the same way and search for the row you want.

#### What does not work, so nobody re-derives it

- `WebFetch` — **403** on every Claude Design URL.
- Navigating straight to `*.claudeusercontent.com` — empty document; it only
  renders inside its parent frame.
- Reading the code viewer's `<textarea>` from the pane, which is what this file
  used to say. The viewer now renders in a **cross-origin** frame, so
  `javascript_tool` sees the chat panel and not a character of the file. It
  returns an empty string rather than an error, which looks exactly like "the
  kit is unreachable" — the assumption that produced GLO-62. `read_page` can
  see the viewer, but only the lines currently scrolled into view.
- Clicking **Copy** and pasting — clipboard reads are denied to the pane.

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
| Shared | `Mock` — the product stand-in; `kind` is dropper/bottle/compact/tube/jar, falling through to `mist` |

`G.Mock` is worth knowing about: the kit draws products as tinted vector shapes
by `kind`, not photographs. It is **ported** as `ProductMock` in DesignSystem
([#56](https://github.com/seanbrasse/glossed/pull/56)) — so a screen that needs
a product on it has the frame's own drawing available and should not reach for
`TypographicTile`, which is the floor for a product whose packaging is unknown.

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
