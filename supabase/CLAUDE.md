# supabase/ — schema, functions, tests

Migrations are a **global lock**: one open migration PR project-wide, and only on a migration ticket. Free-reset until the first real user record; expand-and-contract after (docs/tech/00 §7).

Every user-scoped table ships in the same PR as: RLS enabled + policies, and a pgTAP isolation test (two users, deny-by-id on read/update/delete). A new user-scoped table without an isolation test fails CI — non-negotiable, including hotfixes.

Aggregates store no user identifiers; clients read them only through security-definer RPCs that enforce min-n. Seeds are deterministic and committed — cover every role and lifecycle state, including the ugly ones.

Schema vocabulary matches `docs/domain.md` exactly. snake_case, plural tables, `created_at`/`updated_at` everywhere, soft delete via `deleted_at`.
