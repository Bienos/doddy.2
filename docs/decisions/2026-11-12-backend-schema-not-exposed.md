# Row level security on the backend schema, and Supabase's API roles get no use of it

- **Date:** 2026-11-12
- **Decided by:** proposal, owner approval pending
- **Status:** proposed (branch `claude/backend-schema-not-exposed`)
- **Replaces:** nothing; it backs up ADR-525's "the `anon` and `authenticated` API roles get nothing on it" with a check the server runs itself

## Why
The backend's tables live in the schema `doddy_backend` of the Supabase project `doddy-gateway` (ADR-525). None of them had row level security enabled (read on 12 Nov 2026: 30 tables, 0 with it on). Today `anon` and `authenticated` have no `USAGE` on the schema and no privilege on any of its tables, so the Data API can't read them; that rests on the schema's grants alone, and one later grant, or the schema being added to the Data API's exposed schemas, would open every table to those roles.

## Decision
At every start, after the schema statements and in the same transaction (`SCHEMA_GUARDS` in `backend/src/store.ts`):
- **Row level security on every table** in `doddy_backend` that the backend's role owns and that doesn't have it yet: `ALTER TABLE … ENABLE ROW LEVEL SECURITY`, **no policies and not `FORCE`**. A table's owner isn't held to row level security unless it is forced, so the backend reads and writes as before; any other role that isn't `BYPASSRLS` sees no rows and can change none. Tables added later get it at the next start.
- **No use of the schema for `anon` and `authenticated`**: `REVOKE ALL ON SCHEMA doddy_backend` and on its tables from each of them, only when the role exists (PGlite and plain Postgres have neither) and only when it holds something, inside a `DO` block that turns a refused change into a notice instead of a failed start.

Read on Supabase before writing it (read-only `SELECT`s): every table in `doddy_backend` is owned by the role `doddy_backend` (not a superuser, no `BYPASSRLS`), the backend's connections come in as `doddy_backend` (through Supavisor), so the tables' owner is the backend's own role and RLS without `FORCE` doesn't apply to it. `postgres` and `service_role` have `BYPASSRLS` (the SQL editor and the dashboard are unaffected). The schema itself is owned by `postgres`, so the schema `REVOKE`, run as `doddy_backend`, can only remove grants `doddy_backend` made: on Supabase it is a guard that changes nothing today (neither role has any privilege there); the table `REVOKE` is the backend's own, as their owner.

## Consequences
- The first start after the deploy runs `ALTER TABLE … ENABLE ROW LEVEL SECURITY` once on each table (30 on 12 Nov, plus any table the same deploy adds; a brief exclusive lock each, inside the start-up transaction, like the existing `ADD COLUMN IF NOT EXISTS` statements); later starts change nothing. If a lock can't be had within the 10-second statement timeout, that start fails as a whole (nothing is half-changed) and the next start tries again.
- If the backend ever connects as a role that is neither the tables' owner nor `BYPASSRLS`, it sees no rows. Moving the data to another Postgres must keep the backend's role as the tables' owner, or add policies.
- Rollback: deploying the earlier commit leaves row level security on, which the backend, as the tables' owner, doesn't notice. To turn it off by hand, as the owner role: `ALTER TABLE doddy_backend.<table> DISABLE ROW LEVEL SECURITY` for each table.

## Evidence
`backend/test/schema-not-exposed.test.ts`: every table has `relrowsecurity` on and `relforcerowsecurity` off after the migrations; with `anon` and `authenticated` made in PGlite and granted the schema and its tables, a start takes both away, and `anon`, let in, saw no rows. `npm run typecheck` and `npm test` in `backend/`. Not run: the migration against the hosted Supabase database (it ships with the code and runs at the next deploy).
