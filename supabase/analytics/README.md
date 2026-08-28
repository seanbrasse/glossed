# Analytics templates

Checked-in SQL for the standing questions (`docs/tech/06` §5). Each file is one
question; the weekly sit-down runs them read-only (psql `\i`, or a Metabase
saved question pointed at the same SQL).

These run as a privileged role — `failed_searches` and the `events` family
deliberately have **no user grants** (migrations 0004, 0011). Locally:

```bash
docker exec -i supabase_db_glossed psql -U postgres -d postgres < supabase/analytics/failed-searches-top50.sql
```

| file | question |
|---|---|
| `failed-searches-top50.sql` | the weekly fill list + unmet-demand rollup (PRD §15) |
