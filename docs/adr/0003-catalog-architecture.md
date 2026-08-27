# 0003. Catalog: snapshot backfills once, feeds are the heartbeat, users are the tail

Date: 2026-08-27 | Status: accepted (PRD §15, final)

## Context
Every app in this space dies on the catalog. Steady-state cost must be $0 and nothing metered per user.

## Options
1. Hosted catalog API (per-call) — scales the wrong way on a free app.
2. Scraping — legally messy, brittle.
3. Affiliate feeds (publisher accounts) + one-time licensed snapshot (self-hosted) + user tail.

## Decision
Option 3. GTIN is the universal join key; every record carries `source` + `last_verified`. Snapshot purchased only if free-stack hit rate < 85%. Reformulations fork (never overwrite); merge queue has three verbs (merge / attach-as-variant / fork); user-created products live in `personal` scope and physically cannot pollute the shared catalog; promotion to canonical at three distinct loggers + review.

## Consequences
Easy: new launches via feed diff, zero marginal cost, failed-search queue turns catalog work into a prioritized list. Hard: feed field quality varies (normalization layer), dedupe is the permanent chore (LLM auto-band + one weekly human). Revisit if: merge-queue depth trends up (tune thresholds) or hit rate stalls below target (buy the snapshot).
