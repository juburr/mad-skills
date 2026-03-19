# PostgreSQL RLS Review Checklist

Use this checklist before finalizing a design, review, or migration.

## Scope and context

- [ ] What PostgreSQL version is in scope?
- [ ] Is the access model based on database roles, custom settings, JWT claims, or a mix?
- [ ] Is the environment connection-pooled?
- [ ] Which operations must be supported: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `ON CONFLICT`?
- [ ] Are there views, inheritance, partitioning, or logical replication involved?

## Policy semantics

- [ ] Is RLS actually enabled on the table (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`)?
- [ ] Is default-deny behavior acceptable if no policy matches?
- [ ] Are `USING` and `WITH CHECK` both handled correctly for write policies?
- [ ] Does `UPDATE` need both target-row visibility (`USING`) and resulting-row validation (`WITH CHECK`)?
- [ ] Are `SELECT` policies present where `UPDATE`/`DELETE`/`MERGE`/`ON CONFLICT` need to read rows?
- [ ] If restrictive policies are used, is there at least one permissive policy that can grant access?
- [ ] If `WITH CHECK` is omitted, is the implicit reuse of `USING` intentional?

## Identity and claims

- [ ] Are request attributes transaction-local (`SET LOCAL` / `set_config(..., true)`) rather than session-level?
- [ ] Are hot-path checks using small canonical typed attributes instead of repeatedly parsing a claims blob?
- [ ] Are helper functions row-independent when possible?
- [ ] Is `current_setting(name, true)` used (with `missing_ok`) to avoid errors on absent settings?

## Schema and indexing

- [ ] Are hot-path RLS predicates expressed on planner-friendly scalar or array columns?
- [ ] Are selective equality/range predicates backed by btree indexes?
- [ ] Are array overlap/containment predicates backed by GIN where appropriate?
- [ ] If JSONB is used in policies, would expression indexes or extracted columns be more efficient?
- [ ] Would expression statistics (PostgreSQL 14+) help estimates without adding another index?
- [ ] Are partial indexes actually usable for the predicate shape, or will the planner ignore them?

## Safety

- [ ] Are tests run as a non-owner role, or with `FORCE ROW LEVEL SECURITY`?
- [ ] Does `row_security_active('table_name')` return true in the test execution context?
- [ ] If `SECURITY DEFINER` helpers exist, is `search_path` locked down and `EXECUTE` restricted?
- [ ] Do any views need `security_invoker = true` (PostgreSQL 15+)?
- [ ] Are backup/dump/restore/replication workflows compatible with the policy set?
- [ ] Is `COPY FROM` avoided for RLS-enabled tables (use `INSERT` instead)?

## Verification

- [ ] Can the design be demonstrated with a minimal table and policy example?
- [ ] Is there an `EXPLAIN (ANALYZE, BUFFERS)` plan for representative queries?
- [ ] Has the design been tested with realistic data volumes and the actual application role?
- [ ] Are minor-version security fixes relevant to the deployment baseline?
