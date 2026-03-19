---
name: postgres-rls
description: Guides PostgreSQL row-level security (RLS) policy design, implementation,
  review, debugging, and performance optimization. Use when writing CREATE POLICY
  statements, configuring USING/WITH CHECK clauses, setting up claim-based access
  control (PostgREST, Supabase), using security_invoker views, tuning RLS performance,
  or diagnosing missing or forbidden rows.
---

# PostgreSQL Row-Level Security

RLS is a database-enforced row filter that supplements normal SQL privileges. Once enabled on a table, rows are visible or writable only when at least one applicable policy allows them. If no policy matches, the default is deny-all. RLS does not apply to `TRUNCATE` or `REFERENCES`.

## Core Mental Model

| Clause | Applies to | On false/null |
|---|---|---|
| `USING` | Existing rows (visibility, targetability for UPDATE/DELETE) | Row silently hidden |
| `WITH CHECK` | New/modified row values (INSERT, UPDATE, MERGE) | Error raised |

- `WITH CHECK` runs after `BEFORE` triggers, before other constraints.
- If `WITH CHECK` is omitted from an `UPDATE` or `ALL` policy, the `USING` expression is reused. Make this deliberate, not accidental.

### Policy combination

| Type | Combination | Behavior |
|---|---|---|
| Permissive | OR | Any matching permissive policy grants access |
| Restrictive | AND | All restrictive policies must pass, but only if at least one permissive policy also grants access |

Restrictive policies were added in PostgreSQL 10. If only restrictive policies exist (no permissive), access is denied.

### Who bypasses RLS

| Role | Bypasses RLS? |
|---|---|
| Superuser | Always |
| Role with `BYPASSRLS` attribute | Always |
| Table owner | Yes, unless `FORCE ROW LEVEL SECURITY` is set |
| `pg_read_all_data` / `pg_write_all_data` | No |

## Design Rules

1. **Separate read and write concerns.** Define explicit `USING` and explicit `WITH CHECK` for write policies unless symmetric behavior is intentional.

2. **Remember SELECT dependencies.** `UPDATE`, `DELETE`, `MERGE`, and `INSERT ... ON CONFLICT` often require `SELECT` rights, so `SELECT` policies must also grant access for the operation to succeed.

3. **Use permissive for grant paths, restrictive for safety gates.** Multiple independent access reasons (owner OR group member) are permissive. Universal constraints that must always hold (classification gate) are restrictive.

4. **Prefer explicit per-operation policies** over a single `ALL` policy when read and write visibility differ.

5. **Evaluate views carefully.** By default, the view owner's RLS policies apply. Use `security_invoker = true` (PostgreSQL 15+) when the caller's policies should apply instead.

6. **Handle inheritance/partitioning.** Parent table policies apply to child rows in inherited queries. Child-specific policies only apply when the child is named directly — parent policies are then ignored.

## Identity and Claims Transport

### Transaction-local settings (recommended)

Use `SET LOCAL` or `set_config(name, value, true)` to set request-scoped attributes per transaction. Read with `current_setting(name, true)` (returns NULL if absent instead of erroring; `missing_ok` parameter available since PostgreSQL 9.6).

```sql
BEGIN;
SET LOCAL app.username = 'alice';
SET LOCAL app.groups = '{"engineering","finance"}';
SET LOCAL app.clearance_rank = '2';
-- ... application queries ...
COMMIT;
```

Custom settings must use two-part names (e.g., `app.username`). `SET LOCAL` is automatically unwound at transaction end, making it safe for connection pooling.

**Do not use session-level `SET`** for per-request claims in pooled environments — the setting persists beyond the transaction and can leak to subsequent requests.

### Database role switching

When authorization maps naturally to PostgreSQL roles, `SET LOCAL ROLE` switches identity for the transaction lifetime. PostgREST uses this pattern with JWT-selected roles, making `current_user` and role membership first-class policy inputs.

### Hot-path optimization

- Prefer a small set of canonical typed attributes (`app.username`, `app.groups`, `app.clearance_rank`) over repeatedly parsing a full JWT/claims JSON blob in every row check.
- Wrap row-independent helper functions in `(SELECT ...)` subqueries to encourage the planner to evaluate them once per statement rather than once per row.
- Use typed scalar and array columns for hot-path predicates. If classification data lives in JSONB, surface frequently-tested fields into typed columns, generated columns, or expression indexes.

## Performance and Indexing

### Planner behavior

RLS policy expressions are stored as security-barrier quals. The planner enforces them before user-supplied conditions, except for leakproof functions/operators which may run earlier. PostgreSQL still uses indexes where safe — RLS does not force a sequential scan. PostgreSQL 10 materially improved optimizer knowledge about safe RLS filter placement.

### Indexing rules

| Predicate shape | Index type |
|---|---|
| Equality/range on tenant/owner columns | btree |
| Array overlap (`&&`) or containment (`@>`, `<@`) | GIN with `array_ops` |
| JSONB containment (`@>`) | GIN with `jsonb_path_ops` |
| Repeated JSONB scalar extraction | Expression index or extracted column |

**Do not index every field in a policy.** Index only selective predicates that the planner can actually use.

### When indexes are not the answer

- **Expression statistics** (`CREATE STATISTICS` on expressions, PostgreSQL 14+) can improve planner estimates without index maintenance overhead. Multivariate statistics across columns have been available since PostgreSQL 10.
- **Partial indexes** often disappoint for dynamic per-request predicates — the planner cannot always prove a parameterized query implies the partial predicate.
- **Generated columns** (stored: PostgreSQL 12+, virtual: PostgreSQL 18+) can surface computed values for indexing without expression index overhead.

### General performance rules

- Add normal selective query predicates alongside RLS. RLS is a security boundary, not a substitute for application-side filters, pagination, or time windows.
- Benchmark with the real application role, real request-scoped settings, and realistic data volumes.
- Use `EXPLAIN (ANALYZE, BUFFERS)` to verify the planner is using expected indexes.

## Critical Gotchas

1. **Owner bypass** — Testing as table owner means RLS is not exercised at all unless `FORCE ROW LEVEL SECURITY` is set. Use `row_security_active('table_name')` to confirm.
2. **Silent vs. loud failures** — `USING` silently hides rows; `WITH CHECK` raises errors. Understand which behavior your users will experience.
3. **`ON CONFLICT DO UPDATE`** — Has additional read-path and `WITH CHECK` interactions beyond a plain `INSERT`. The `SELECT`, `INSERT`, and `UPDATE` policy interactions must all be considered.
4. **`MERGE`** (PostgreSQL 15+) — No separate MERGE policy type. PostgreSQL applies `SELECT`, `INSERT`, `UPDATE`, and `DELETE` policies corresponding to the actual actions taken.
5. **`COPY FROM`** — Not supported for tables with RLS. Use `INSERT` statements instead. `COPY TO` respects `SELECT` policies.
6. **Logical replication** — Only superusers, `BYPASSRLS` roles, and table owners can replicate into RLS-protected tables.
7. **`SECURITY DEFINER` helpers** — Must harden `search_path` (lock to specific schemas, exclude `pg_temp`) and restrict `EXECUTE` privileges. `LEAKPROOF` is even more sensitive — only a superuser can declare it.
8. **`pg_dump` behavior** — By default sets `row_security = off`, which errors if the dumping role cannot bypass RLS. Use `--enable-row-security` to dump only visible rows. Use `--no-policies` (PostgreSQL 18+) to omit policies from dump output.

## Testing

```sql
-- Verify RLS is active for the current user
SELECT row_security_active('my_table');

-- Test as a non-owner role with real settings
BEGIN;
SET LOCAL ROLE app_user;
SET LOCAL app.username = 'alice';
SET LOCAL app.groups = '{"engineering"}';

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM my_table WHERE some_column = 'value' LIMIT 50;

ROLLBACK;
```

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/reference.md` | Detailed semantics, planner internals, design patterns, version history, operations, anti-patterns | Version-sensitive questions, performance tuning, operational concerns (dump/restore/replication), or deep semantic questions |
| `references/checklist.md` | Review checklist covering scope, semantics, identity, indexing, safety, and verification | Before finalizing any RLS design or review |
| `references/examples.sql` | Complete SQL patterns: ownership, group overlap, classification gates, hybrid JSONB, helper functions, diagnostics | When concrete SQL is needed for implementation |
