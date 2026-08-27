# 0001. Supabase as the backend platform

Date: 2026-08-27 | Status: accepted

## Context
iOS-only client needs: Postgres (PRD-decided self-hosted catalog snapshot, trigram dedupe, crosswalk self-joins), auth limited to Sign in with Apple + phone OTP (no email/password), per-user data isolation, background jobs (feed diffs, aggregates, LLM parsing), and a $10–35/mo run rate.

## Options
1. **Supabase** — managed Postgres + Auth (native Apple `signInWithIdToken`, phone OTP via Twilio/MessageBird/Vonage) + RLS + Edge Functions + pg_cron; GA Swift SDK.
2. Custom server (Vapor/Node) + managed Postgres — full control; we build auth, jobs, and ops ourselves.
3. Firebase — fast start; no Postgres, so the catalog joins, trigram dedupe, and co-occurrence queries don't fit.

## Decision
Supabase. RLS doubles as the handbook's database-layer isolation backstop; both auth methods are first-party; it is plain Postgres underneath (escape hatch preserved); free tier fits the budget.

## Consequences
Easy: auth, per-user RLS, SQL-first aggregates, local dev via `supabase start`, branching for previews. Hard: long-running jobs must fit Edge Function limits (chunk feed diffs); PostgREST shapes the API (custom RPCs where it doesn't fit). Revisit if: job complexity outgrows Edge Functions or costs invert at scale — migration path is ordinary Postgres + any host.
