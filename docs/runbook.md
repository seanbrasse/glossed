# Runbook

Operational procedures. Written to be followable by someone who has never done
the thing before — if a step assumes context you only get from having been here,
it is a bug in this file.

`BACKLOG.md` tracks the sections still missing (deploy, rollback, restore drill,
common failures). This file currently covers **moderation** ([GLO-144](https://linear.app/glossed/issue/GLO-144)).

---

## 1. Moderation queue — Phase 1.5

### 1.1 Where the queue is

**Supabase Studio, and nothing else.** `tech/02` §7 settled this: v0 is one reviewer
over two content types, which is a Studio-sized problem. There is deliberately no
bespoke internal UI, and none is being built — a purpose-built surface brings its
own auth, deploy target and maintenance for a queue that may never get deep.

**Revisit when the manual path hurts**, not before: more than roughly an hour a
week in Studio, or a second person reviewing. That trigger is on `BACKLOG.md`.

There is **no `reviewer` role in the database.** Reviewing happens as
`service_role` through Studio. If you find yourself wanting to add an
`authenticated` reviewer policy so the app can show a queue — stop. That is a
role, and a role is a Phase-2-sized change (`domain.md` §4's `reviewer` row is
satisfied by service access until then).

### 1.2 What lands in the queue

Two independent pipelines, and they fail in opposite directions on purpose:

| Pipeline | Table | Default state | Fails to |
|---|---|---|---|
| **Text** — bio, handle, collection title, routine title, linked social | `public_texts` | `pending` | **closed** — a model error or timeout leaves it `pending`, never `approved`. An unavailable moderator is not an approval. |
| **Images** — swatches | `swatches` | `pending_review` | **closed** — the public read policy tests `state = 'public'`, not `state <> 'removed'` |
| **Reports** — filed by users against either | `reports` | `open` | n/a — human decision |

The render rule both pipelines exist to protect: **a public surface reads only
`state = 'approved'` / `state = 'public'`.** A pending edit renders the
previously approved body, or nothing. Never the pending text.

### 1.3 Triage

Work `reports` where `state = 'open'`, oldest first, except that `underage` and
`self_harm` jump the queue (§1.5, §1.6).

For each report:

1. **Read the subject, not just the report.** `subject_kind` + `subject_id` tell
   you what to open. A report is a signal that someone objected, not a finding.
2. **Set `state = 'reviewing'`** before you start, so a second person does not
   pick up the same row.
3. **Decide** — see the codes below.
4. **Write `decided_by`, `decided_at`, `decision_note`.** The note is for the
   next reviewer and for you in six months. "Not a violation" is not a note;
   "product name, not an impersonation attempt" is.
5. **Notify both parties** (§1.7).

### 1.4 Decision codes

| `state` | Means | Effect on the content | Effect on the account |
|---|---|---|---|
| `dismissed` | No violation | none | none |
| `actioned` | Violation confirmed | text → `rejected`; swatch → `removed` | see escalation below |

The `reports` row itself is **never deleted**. It outlives the content it
describes by design — T&S retention is 2 years (`domain.md` §6), and both user
references are `on delete set null` so the record survives account deletion with
the personal fields gone.

**Escalation is by pattern, not by severity of one item.** A first `spam` is a
removal. A third `spam` from the same account in a month is a conversation. There
is no automated strike system in 1.5 and adding one is not a reviewer decision.

### 1.5 The `underage` reason has its own path

**It is not the harassment path and must not be worked as one.**

A report that a user is under 13 is a COPPA matter, not a content matter. The
account gate is at signup (`domain.md` §3.4 — under-13 is a hard server-side
block on the birthday), so an `underage` report is a claim that the gate was
defeated by a false birthday.

1. Do **not** action the content and move on. The content is not the issue.
2. Escalate to the named owner (§1.8) the same day. This is not a queue item to
   batch.
3. Do **not** contact the reported user asking them to confirm their age. That
   invites a second false answer and creates a record of us soliciting it.
4. Preserve everything. Do not delete the account or its content while the
   question is open — see §2.3 on the preservation rule, which applies here too.

### 1.6 `self_harm` is a safety path, not a moderation one

Remove nothing reflexively. The priority is the person, not the post. Escalate
to the named owner the same day, and surface support resources to the reporter
if the product has a path to do so. This section is deliberately short because
the real procedure needs input this project has not yet obtained — see §3.

### 1.7 The notification rule

`domain.md` §3.5: **reporter and poster are both notified** of the outcome. Not
one or the other, and not silence.

The reporter needs to know their report was read — otherwise reporting feels
like shouting into a well and people stop doing it, which costs us the signal.
The poster needs to know what happened to their content and why, or removal
reads as a bug.

Say what happens, not what was decided about the person. "This swatch was
removed because it does not show a product on skin" — not "your report was
upheld."

### 1.8 Named owner

**Unassigned.** This runbook cannot be operative until a specific human owns
§1.5, §1.6 and §2. Sean to name one before the first swatch goes public.

---

## 2. NCMEC runbook — DRAFT, not operative

> ⚠️ **This is a draft written ahead of need, and it is not legal advice.**
> It must be reviewed by counsel before it governs anything. It exists because
> the first phase with user photos is the wrong place to start writing it:
> Phase 1.5 has one photo surface and one reviewer, and Phase 2 has looks, feeds
> and comments. Phase 2 should inherit a draft, not a blank page.
>
> **Do not treat unreviewed sections as procedure.** Where this draft is unsure,
> it says so rather than guessing.

### 2.1 What triggers it

Apparent child sexual abuse material (CSAM) identified in any user-uploaded
image — in 1.5, that means a swatch — whether surfaced by the automated image
moderation pass, a user report (`nudity` or `underage`), or a reviewer's own
eyes.

**The threshold for triggering this path is suspicion, not certainty.** A
reviewer is not required to be sure, and should not try to become sure by
looking harder.

### 2.2 Immediate actions

1. **Stop looking.** Do not view further, do not download, do not share
   internally to get a second opinion, do not paste it into any tool. Additional
   viewing is not diligence.
2. **Make it non-public immediately** — `state = 'removed'`.
3. **Escalate to the named owner (§1.8) immediately.** Not the end of the shift.
4. **Do not contact the uploader.** Not a warning, not a question, nothing.

### 2.3 The preservation rule — the one that is counterintuitive

**Do not delete the content.** US federal law requires preservation of reported
material and associated records for a period after a report is filed, and
deleting it can destroy evidence.

This directly contradicts the instinct to purge, and it contradicts our normal
deletion posture — `domain.md` §6 says account deletion destroys user content.
**This path overrides that**, and the override needs to be built into whatever
implements deletion, not left to a reviewer to remember under pressure.

Preserve: the image, its storage key, the `swatches` row, the uploader's account
identifiers, upload timestamps, and any IP/device records the platform holds.

**Open for counsel:** the exact retention period, and whether our current
account-deletion path would violate it. This is the single most important
question in this draft.

### 2.4 Reporting

Reports go to NCMEC's CyberTipline. **Open for counsel:** who is registered to
file, what the filing SLA is, and whether we have an obligation we are currently
not meeting by not being registered.

### 2.5 What this draft does not yet cover

- Registration status with NCMEC
- Retention periods and their interaction with account deletion (§2.3)
- Whether hash-matching against known-CSAM databases is available to us at our
  scale, and what it would obligate
- Jurisdictions outside the US
- Reviewer welfare: nobody should work this queue alone, unprepared, or without
  a way to stop

---

## 3. Before this file is operative

- [ ] A named human owns §1.5, §1.6 and §2 (Sean)
- [ ] §2 reviewed by counsel; every "open for counsel" resolved
- [ ] §2.3's preservation rule reconciled with the account-deletion path in code
- [ ] §1.6 written properly with appropriate input
- [ ] Deploy, rollback, restore-drill and common-failure sections added (`BACKLOG.md`)
