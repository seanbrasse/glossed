-- 0028 · Reports. GLO-140 (GLO-31 1/5). docs/tech/02 §7.
--
-- Report and block on profiles ship day one of this phase. `blocks` already
-- exists (0020) because can_view could not be written without it, so blocking
-- has been available since the moment anything became visible. This is the
-- reporting half.

create type report_state   as enum ('open', 'reviewing', 'actioned', 'dismissed');
create type report_subject as enum ('profile', 'handle', 'bio', 'collection', 'routine', 'swatch', 'linked_social');

-- REPORTS OUTLIVE THEIR SUBJECTS. T&S retention is 2 years and a report
-- survives account deletion with the personal fields gone (domain.md §6).
--
-- Hence `on delete set null` on BOTH user references rather than cascade: a
-- cascade would delete the moderation record along with the account it exists
-- to remember, which is precisely backwards. The row is the institutional
-- memory; the identities are the perishable part.
create table reports (
    id              uuid primary key default gen_random_uuid(),
    reporter_id     uuid references auth.users (id) on delete set null,
    subject_kind    report_subject not null,
    subject_id      uuid,
    subject_user_id uuid references auth.users (id) on delete set null,
    reason          text not null check (reason in
                        ('impersonation', 'harassment', 'spam', 'nudity',
                         'ai_generated', 'underage', 'self_harm', 'other')),
    detail          text,
    state           report_state not null default 'open',
    decided_by      uuid,
    decided_at      timestamptz,
    decision_note   text,
    created_at      timestamptz not null default now()
);

-- The queue is worked oldest-first except that `underage` and `self_harm` jump
-- it (runbook §1.5, §1.6), so the index matches how the queue is actually read.
create index reports_open_queue on reports (created_at) where state = 'open';
create index reports_subject on reports (subject_kind, subject_id);

alter table reports enable row level security;

-- NOT `for all`. A broad policy would OR with the narrow ones and hand a
-- reporter UPDATE on their own filed report — see 0026, where exactly that
-- shape let a minor post a swatch. Permissive policies combine with OR.
--
-- There is deliberately NO update or delete policy: a filed report is not
-- editable or retractable by its reporter. It is a record of something having
-- been said, and the reviewer's decision is the only thing that moves it.
create policy reports_insert_own on reports for insert
    to authenticated
    with check (reporter_id = (select auth.uid()));

create policy reports_read_own on reports for select
    to authenticated
    using (reporter_id = (select auth.uid()));

-- There is NO `reviewer` role in the database, and this migration does not add
-- one. Moderation v0 is Supabase Studio as service_role (docs/runbook.md §1.1);
-- adding an `authenticated` reviewer policy means adding a role, which is a
-- Phase-2-sized change. domain.md §4's `reviewer` row is satisfied by service
-- access until then.
--
-- Do not fill this gap with a policy because the permission matrix has a row
-- for it.

-- Privilege and policy agree (the 0024 rule, applied at creation this time
-- rather than swept up afterwards — see 0027 for what happens otherwise).
-- anon never reports: reporting requires an account.
revoke all on table reports from anon;

comment on table reports is
    'Outlives the content and the accounts it describes: 2-year T&S retention, both user refs `on delete set null` so the record survives deletion with personal fields gone. GLO-140, docs/tech/02 §7, domain.md §6.';
