-- 0045 · Bios are approved on write, for as long as the cohort is the beta.
-- GLO-207. Sean's ruling, Aug 30, asked directly: "Auto-approve bios for the
-- beta cohort."
--
-- WHAT IT FIXES. `public_texts.state` defaults to 'pending', 0023's writer set
-- 'pending' on insert AND on every edit, and public_profile reads the bio only
-- `where state = 'approved'`. Moderation is parked (Sean, Aug 29 — "skip the
-- moderation for now"): the text-moderation function exists and nothing runs
-- it. So a bio was written successfully, reported no error, and never appeared.
-- Ever. The same shape as GLO-189, where copy promised a review nobody
-- performed.
--
-- THE HONEST LIMIT OF THIS MIGRATION, stated because it will not be obvious
-- later: "the beta cohort" IS NOT EXPRESSIBLE HERE. There is no cohort table,
-- no invite table, no feature flag — checked against the live database, not
-- inferred from these files. While the beta is closed and hand-recruited
-- (GLO-192) every user is the cohort, so approving on write is a faithful
-- reading of the ruling TODAY. It stops being faithful the day the app opens
-- up, and nothing in this schema would notice.
--
-- So the switch is named, the approvals are marked, and both are tested. An
-- auto-approve that outlives its cohort is unmoderated user text published at
-- scale, which is the risk the gate existed for in the first place.

-- ---------------------------------------------------------------------------
-- The switch. One line to flip, the same shape as min_n_faceoffs() and the
-- other constants kept auditable in one place (ADR 0006).
--
-- BEFORE PUBLIC LAUNCH: flip this to false and work the backlog below. Also
-- recorded in docs/BACKLOG.md, because a migration comment is not where anyone
-- looks when a phase opens.
-- ---------------------------------------------------------------------------
create or replace function bios_auto_approve() returns boolean
language sql immutable as $$ select true $$;

comment on function bios_auto_approve() is
    'BETA ONLY (GLO-207, Sean Aug 30). Bios skip review while the cohort is closed and hand-recruited. Flip to false before public launch and work the backlog: select * from public_texts where kind = ''bio'' and verdict ? ''auto_approved'';';

-- ---------------------------------------------------------------------------
-- The writer. Bios land 'approved' while the switch is on; everything else is
-- unchanged and still lands 'pending'.
--
-- Handles are deliberately untouched. A claimed handle already renders
-- unfiltered by moderation state (GLO-187) — nothing acts on a rejected one and
-- there is no rename or release flow — so its public_texts row is a review
-- record, not a gate. Collections and routines keep 'pending': not in the
-- ruling, and no surface reads them yet.
--
-- The approval is MARKED rather than silent. `verdict` records that nobody
-- looked, so "every bio that has never been reviewed" is a query instead of an
-- assumption, and staffing moderation later starts with a list rather than a
-- guess. `model` stays null — no model ran, and writing one there would claim
-- a review that did not happen.
-- ---------------------------------------------------------------------------
create or replace function set_public_text(p_kind public_text_kind, p_subject uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
    v_user  uuid := (select auth.uid());
    v_auto  boolean := (p_kind = 'bio' and bios_auto_approve());
    v_state moderation_state := case when v_auto then 'approved' else 'pending' end;
    v_verdict jsonb := case when v_auto
        then jsonb_build_object('auto_approved', true, 'reason', 'beta cohort, moderation not staffed')
        end;
    v_id    uuid;
begin
    if v_user is null then
        raise exception 'sign in first' using errcode = 'insufficient_privilege';
    end if;
    insert into public_texts (user_id, kind, subject_id, body, state, verdict, decided_at)
    values (v_user, p_kind, p_subject, p_body, v_state, v_verdict,
            case when v_auto then now() end)
    on conflict (user_id, kind, subject_id) do update
        -- An edit re-enters review, unless the switch says there is no review
        -- to re-enter. 0023's "always" is no longer true and does not pretend
        -- to be.
        set body = excluded.body,
            state = excluded.state,
            model = null,
            verdict = excluded.verdict,
            decided_at = excluded.decided_at,
            updated_at = now()
    returning id into v_id;
    return v_id;
end $$;

grant execute on function bios_auto_approve() to anon, authenticated;

comment on function set_public_text(public_text_kind, uuid, text) is
    'The only writer for user-authored public text. state is never client-declared. Bios land approved while bios_auto_approve() is true (GLO-207) and carry verdict.auto_approved so the unreviewed set stays queryable; everything else lands pending.';
