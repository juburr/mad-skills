# PostgreSQL Row-Level Security Reference

Detailed reference for designing, reviewing, and optimizing PostgreSQL row-level security policies. Supplements the core rules in SKILL.md with deeper semantics, planner behavior, design patterns, version history, operational caveats, and anti-patterns.

## Definitions

- **Row-Level Security (RLS)**: A per-table, database-enforced authorization layer on top of standard SQL privileges. Once enabled, ordinary users can only see or modify rows that pass at least one applicable policy. `TRUNCATE` and `REFERENCES` are outside RLS scope.
- **`USING`**: Applies to existing rows. Determines visibility in reads and targetability for update/delete. False or null results silently hide the row.
- **`WITH CHECK`**: Applies to proposed new row values from `INSERT`, `UPDATE`, and `MERGE` actions. False or null results raise an error and abort the statement. Enforced after `BEFORE` triggers and before other constraints.
- **Permissive policies**: Combine with logical OR. Any matching permissive policy grants access.
- **Restrictive policies**: Combine with logical AND, but only matter if at least one permissive policy grants access first. If only restrictive policies exist, access is denied. Added in PostgreSQL 10.
- **Owner bypass**: Table owners bypass RLS unless `ALTER TABLE ... FORCE ROW LEVEL SECURITY` is set. Superusers and roles with `BYPASSRLS` also bypass RLS. `pg_read_all_data` and `pg_write_all_data` do not bypass RLS on their own.
- **Security-barrier qualification**: The right mental model for planner behavior. PostgreSQL stores policy expressions as security-barrier quals attached to the table. User conditions are generally enforced after the policy expression, except that leakproof functions and operators may be applied earlier.
- **Request-scoped settings / custom GUCs**: Application-defined two-part setting names (e.g., `app.username`, `app.groups`) set per transaction with `SET LOCAL` or `set_config(..., true)` and read with `current_setting(name, true)`. PostgreSQL accepts any two-part parameter name as a custom placeholder.
- **`security_invoker` views** (PostgreSQL 15+): Execute underlying-view permission and RLS checks as the caller instead of the view owner. Often the correct choice when exposing RLS-protected tables through views.

## Decision Matrix

| Situation | Recommended approach |
|---|---|
| Row visibility control | `SELECT ... USING (...)` policy |
| Validate proposed rows on insert | `INSERT ... WITH CHECK (...)` policy |
| Both old-row targeting and new-row validation | `UPDATE ... USING (...) WITH CHECK (...)` |
| Multiple independent grant paths (owner OR group) | Permissive policies |
| Universal safety gate (classification check) | Restrictive policy |
| Authorization maps to database roles | Role switching with `SET LOCAL ROLE` |
| Claims/attributes don't map to roles | Transaction-local custom settings |
| Views over RLS tables where caller's policies should apply | `security_invoker = true` views |
| Hot-path predicates on JSONB fields | Hybrid design: typed columns, generated columns, or expression indexes for frequently-tested values |

## Core Semantics in Detail

### SELECT policy scope

`SELECT` policies are not purely read-only concerns. PostgreSQL applies them whenever `SELECT` rights are required on the relation. This affects:

- **`UPDATE`**: Typically needs `SELECT` rights to read columns in `WHERE`, `RETURNING`, or `SET` expressions. Both `SELECT` and `UPDATE` policies must grant access.
- **`DELETE`**: Usually needs `SELECT` rights for `WHERE` or `RETURNING` clauses. Both `SELECT` and `DELETE` policies must grant access.
- **`INSERT ... ON CONFLICT DO UPDATE`**: Requires `SELECT` permissions on the relation. Rows proposed for insertion are checked using `SELECT` policies. The `ON CONFLICT DO UPDATE` path applies `UPDATE` policies.
- **`MERGE`**: Requires `SELECT` permissions on both source and target relations. Each relation's `SELECT` policies are applied before they are joined.

### UPDATE split semantics

For `UPDATE`, the `USING` clause decides which existing rows can be targeted, while `WITH CHECK` decides whether the resulting updated rows may be stored. If `WITH CHECK` is omitted for an `UPDATE` or `ALL` policy, PostgreSQL reuses the `USING` expression. This shortcut is sometimes desirable (symmetric policies) but should be deliberate.

### MERGE behavior

`MERGE` (PostgreSQL 15+) has no separate RLS policy type. PostgreSQL applies the `SELECT`, `INSERT`, `UPDATE`, and `DELETE` policies that correspond to the actions actually taken by each `WHEN` clause. Similarly, `INSERT ... ON CONFLICT DO UPDATE` has extra read-path and `WITH CHECK` subtleties.

## Request Identity and Claims Transport

### Role-based identity

The cleanest role-based pattern lets the database role itself be the authorization identity. PostgREST implements this: when a JWT contains a valid role claim, PostgREST switches to that role with `SET LOCAL ROLE ...` for the request lifetime, making `current_user` and role membership first-class policy inputs.

### Transaction-local settings

For attributes that don't map to database roles, use transaction-local custom settings:

- Custom settings must have two-part names (e.g., `app.username`).
- `SET LOCAL` lasts only for the current transaction and is automatically unwound at transaction end.
- `set_config(name, value, true)` is the function equivalent for transaction-local writes.
- `current_setting(name, true)` returns `NULL` if the setting is absent (PostgreSQL 9.6+).
- `SET LOCAL` inside a function with its own `SET` clause is restored on function exit.

Session-level `SET` can persist beyond a request in pooled applications unless the pooler or framework resets it correctly. Transaction-local settings avoid this risk.

### JWT claims

PostgREST exposes request headers, cookies, and JWT claims as transaction-scoped settings, including `request.jwt.claims` as JSON. For flexible policy logic this is useful, but the better high-volume default is to distill the JWT into a few canonical typed attributes for the hot path and keep the full claims blob only for low-frequency cases.

## Design Patterns

### Pattern 1: Username ownership

A row-local ownership column (`owner_username text NOT NULL`) protected with equality predicates against `current_setting('app.username', true)` or `current_user`. Always pair with a btree index on the owner column.

### Pattern 2: Array-based group overlap

When a row stores allowed groups as `text[]`, use array overlap (`&&`) or containment operators (`@>`, `<@`). PostgreSQL's built-in GIN `array_ops` operator class supports these operators for indexing. Use `&&` for "user is in at least one allowed group" and `<@` for "all required items are present."

### Pattern 3: Classification gate with AND logic

Common enterprise pattern: group match AND classification match. Surface classification into planner-friendly typed columns:

- `classification_level_rank integer` — user's rank must meet or exceed the row's required rank
- `required_caveats text[]` — row's caveats must be contained within user's caveats (`<@`)
- `allowed_countries text[]` — user's countries must overlap row's countries (`&&`)
- Optional source metadata in `classification jsonb`

Encode as either one explicit `AND` policy or as a permissive grant path plus a restrictive classification gate.

### Pattern 4: Hybrid JSONB design

When the source-of-truth access model is JSONB, avoid repeated ad-hoc JSON extraction in hot-path policy expressions. Better approaches:

- Stored or virtual generated columns that mirror the JSONB fields
- Expression indexes on the specific JSON paths
- Maintained physical columns updated via triggers or application code

PostgreSQL's expression indexes and statistics tooling works better with typed predicates than with repeated JSON parsing.

## Performance and Planner Behavior

### Security-barrier execution model

PostgreSQL stores policy expressions as security-barrier quals. The security ordering is earlier and stronger than ordinary user predicates, but PostgreSQL still plans the whole query and can use indexes where safe. The answer to "does PostgreSQL first apply RLS to every row and only then apply my WHERE clause?" is nuanced — the planner optimizes the full query while preserving security guarantees.

PostgreSQL 10 improved this area significantly by giving the optimizer better knowledge about where it can safely place RLS filter conditions.

### Index strategy

Do not index every field mentioned in a policy. Index the predicate shapes that are both selective and planner-friendly:

- **Equality and range checks** on tenant/owner columns → btree indexes
- **Array overlap/containment** → GIN indexes with `array_ops`
- **JSONB containment** → GIN with `jsonb_path_ops`
- **Repeated JSONB scalar extraction** → expression indexes or extracted columns

Expression indexes accelerate reads but add write maintenance cost. The derived expression must be computed for each insert and non-HOT update. This tradeoff is acceptable when retrieval speed matters more than write throughput.

### Partial indexes

Partial indexes can be powerful but only when the planner can prove the query logically implies the partial-index predicate. PostgreSQL does not have a general theorem prover, and parameterized conditions frequently prevent recognition. This is why partial indexes often disappoint for highly dynamic per-request predicates.

### Expression statistics

Expression statistics (`CREATE STATISTICS` on expressions) are underused in RLS tuning. Univariate statistics on a single expression can provide estimate improvements similar to an expression index without index maintenance overhead.

Note: multivariate statistics across columns (`ndistinct`, `dependencies`) were introduced in PostgreSQL 10. Expression-level statistics were added in PostgreSQL 14. For RLS tuning, expression statistics on policy-relevant expressions are typically the more useful feature.

### Helper function costs

Functions in policies are potential per-row cost centers. If a function returns a fixed value for the whole statement (e.g., `current_setting`), wrapping the call in `(SELECT ...)` can encourage initPlan-style evaluation so the result is computed once rather than per-row. This is a planner optimization pattern, not a guarantee — verify with `EXPLAIN`.

Additionally, do not rely on RLS as the only filter. Adding normal query filters (WHERE clauses, pagination, time windows) alongside RLS improves plan quality and reduces unnecessary work.

## Views, Inheritance, and Helpers

### Views

By default, row-security policies of the **view owner** apply to underlying relations. If the view has `security_invoker = true` (PostgreSQL 15+), the policies and permissions of the **invoking user** apply instead. Evaluate deliberately whether each view over an RLS-protected table should use `security_invoker`.

### Inheritance

For inheritance-style hierarchies, PostgreSQL applies the **parent table's** policies to rows coming from child tables during inherited queries. A child table's own policies only apply when the child is named directly; parent policies are then ignored. This is a major gotcha for inheritance-based partitioning or mixed parent/child designs.

### SECURITY DEFINER helpers

`SECURITY DEFINER` functions are sometimes needed to query auxiliary tables that the caller cannot read directly. Critical safety rules:

- **Harden `search_path`**: Set it explicitly in the function to exclude writable schemas, especially `pg_temp`.
- **Restrict `EXECUTE`**: Grant only to roles that need the function.
- **`LEAKPROOF`**: Only a superuser can declare it. It directly affects whether PostgreSQL may execute the function ahead of security conditions. Use with extreme caution.

## Advanced Caveats

### Referential-integrity and unique-check bypass

Referential integrity checks — unique/primary key constraints and foreign key references — always bypass row security to ensure data integrity is maintained. A failed foreign key or unique constraint error can reveal whether a specific row exists in another table, even if RLS would otherwise hide it. This is a limited information leak, not a full bypass, but it matters in high-sensitivity designs. If row existence itself is sensitive, consider whether constraint error messages could be an unacceptable side channel.

### Race conditions in policy subqueries

In `READ COMMITTED` isolation, when a target row is locked (e.g., via `SELECT ... FOR UPDATE`), the waiting transaction re-reads the updated target row after the lock is released. However, policy subqueries against other tables (e.g., a group-membership lookup) are not re-evaluated — they retain the snapshot taken at query start. This creates a TOCTOU window: a user's privilege in the referenced table may have been revoked by the concurrent transaction that released the lock, but the policy subquery still sees the pre-revocation snapshot. Mitigations include using `FOR SHARE` in policy subqueries (with performance and privilege tradeoffs), taking `ACCESS EXCLUSIVE` locks on referenced security tables during updates, or waiting for concurrent transactions to finish after security-relevant changes.

## Operations

### pg_dump and restore

- The `row_security` GUC controls behavior: when `on`, policies apply normally; when `off`, PostgreSQL raises an error instead of silently filtering rows.
- `pg_dump` sets `row_security = off` by default to avoid silently incomplete dumps. If the dumping role cannot bypass RLS, an error is raised.
- `--enable-row-security` tells `pg_dump` to dump only the rows visible to the dumping role instead of erroring.
- `--no-policies` (PostgreSQL 18+) omits row-security policies from dump output, useful when the target environment has a different policy model.
- `COPY FROM` during restore does not support row security. `INSERT`-format dumps are the safer choice in RLS-constrained restore workflows.

### COPY

- `COPY TO` respects `SELECT` policies.
- `COPY FROM` is not supported for tables with row-level security enabled. Use equivalent `INSERT` statements instead.

### Logical replication

Because row-security policies are not checked in the logical replication path, only superusers, roles with `BYPASSRLS`, and table owners can replicate into tables with RLS policies. Surface this limitation any time RLS tables participate in logical-replication topologies.

### Testing

Test with the actual application role and actual request-scoped settings, not as table owner. Use `row_security_active(table)` to confirm RLS is active in the test context.

## Version History

| Version | RLS-relevant changes |
|---|---|
| **9.5** | Introduced RLS: `CREATE/ALTER/DROP POLICY`, `ALTER TABLE ... ENABLE/DISABLE ROW LEVEL SECURITY` |
| **9.5.10** | Fixed `INSERT ... ON CONFLICT DO UPDATE` so permissions and RLS policies are checked correctly, including the update path's interaction with `SELECT` policies |
| **9.5.20** | Fixed handling of whole-row variables in `WITH CHECK OPTION` and RLS policy expressions |
| **9.6** | Added `missing_ok` argument to `current_setting()`, allowing absent settings to return NULL instead of error |
| **9.6.13** | Tightened rules around leaky selectivity estimators so RLS could not be bypassed through statistics inference |
| **10** | Added restrictive policies. Improved optimization of queries affected by RLS. Introduced `CREATE STATISTICS` (multivariate) |
| **12** | Added stored generated columns, useful for surfacing JSON-derived access-control attributes into indexable columns |
| **14** | Added expression-level statistics in `CREATE STATISTICS`, enabling better planner estimates on policy-relevant expressions without index overhead |
| **15** | Added `MERGE` (no separate RLS policy type). Introduced `security_invoker` views. Logical replication into RLS tables restricted to superusers/BYPASSRLS/owners |
| **13.17 / 14.14 / 15.9 / 16.5 / 17.1** | Fixed cached-plan issue: plans now marked dependent on calling role when RLS applies to non-top-level table references (backported to all supported branches) |
| **18** | Added virtual generated columns (now the default kind). Added `--no-policies` for `pg_dump`/`pg_dumpall`/`pg_restore` |

## Anti-patterns

1. **Testing as table owner** — Owner bypass means the tests are not exercising RLS at all. Always test as a non-owner role or with `FORCE ROW LEVEL SECURITY`.

2. **Session-level SET for per-request claims** — In pooled systems, session-level settings risk cross-request leakage. Use `SET LOCAL` or `set_config(..., true)` for transaction-scoped attributes.

3. **Parsing full JWT in every policy row check** — Extracting claims from JSON on every row is expensive. Distill the few stable attributes needed into typed canonical settings or columns.

4. **JSONB-only classification predicates** — Encoding high-frequency classification checks entirely as JSONB predicates when the same handful of attributes are tested on nearly every request. Hybrid or extracted-column designs are easier to index and explain.

5. **Missing SELECT policies for writes** — Assuming an `UPDATE` or `DELETE` policy alone is enough, even though the statement also requires `SELECT` access to read target rows.

6. **Nested EXISTS subqueries in policies** — Hiding complex auxiliary-table access inside row-by-row `EXISTS` subqueries, especially when those tables also have RLS. Creates performance and debugging problems. Consider `SECURITY DEFINER` helpers (with proper hardening) instead.

7. **Partial indexes for dynamic predicates** — Creating partial indexes for per-request predicates and expecting the planner to use them automatically. PostgreSQL often cannot prove parameterized queries imply partial predicates.

8. **RLS as the only filter** — Omitting normal selective query predicates in the application and relying entirely on RLS. Hurts plan quality and wastes work.

9. **Default-owner views over RLS tables** — Exposing RLS tables through views without `security_invoker` when caller-scoped policies are intended. The view owner's policies apply by default, not the caller's.

## Implementation Checklist

1. **Pin the PostgreSQL version** and note whether minor-release security fixes are relevant.
2. **Choose the identity transport**: role-switching, custom transaction-local settings, JWT claims JSON, or a hybrid. Prefer transaction-local canonical attributes for hot paths.
3. **Model semantics explicitly**: decide row visibility, target-row eligibility, and resulting-row validity separately. For writes, prefer explicit `USING` plus explicit `WITH CHECK`.
4. **Choose planner-friendly schema shapes** for hot predicates: btree-friendly scalars, GIN-friendly arrays, and extracted/generated fields where repeated JSONB parsing would otherwise sit in the policy.
5. **Add only the indexes that match real predicate shapes**. Consider expression statistics when better estimates matter more than another index.
6. **Review views, inheritance, and helper functions**. Decide whether views should be `security_invoker`, whether parent/child policy behavior is acceptable, and whether any `SECURITY DEFINER` helper is hardened correctly.
7. **Test as the real role** with real settings. Use `row_security_active()`, representative queries, and `EXPLAIN (ANALYZE, BUFFERS)`.
8. **Audit operational workflows**: dump/restore, `COPY`, logical replication, and emergency admin access.

## Recommended Default Architecture

For the most common application pattern — per-user ownership, group overlap, and classification-like AND gates:

- Transaction-local canonical settings for request identity and claims
- Typed columns for hot-path access-control attributes
- Permissive policies for grant paths, restrictive policies for universal safety gates
- btree and GIN indexes aligned to actual predicate shapes
- Non-owner or forced-RLS testing with `EXPLAIN` and realistic query filters

This is not the only correct design, but it is the most robust default for maintainability, explainability, and performance.
