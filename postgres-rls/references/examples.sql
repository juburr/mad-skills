----------------------------------------------------------------------
-- PostgreSQL RLS Example Patterns
--
-- These examples use transaction-local custom settings for request
-- identity. In application code, set these per transaction:
--
--   BEGIN;
--   SET LOCAL app.username = 'alice';
--   SET LOCAL app.groups = '{"engineering","finance"}';
--   SET LOCAL app.clearance_rank = '2';
--   SET LOCAL app.countries = '{"US","CA"}';
--   SET LOCAL app.caveats = '{"project-x","m-and-a"}';
--   ... application queries ...
--   COMMIT;
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Helper functions for reading request-scoped attributes
----------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS app;

-- Returns the current request username, or NULL if not set.
CREATE OR REPLACE FUNCTION app.current_username()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT current_setting('app.username', true)
$$;

-- Returns the current request groups as text[], or empty array if not set.
CREATE OR REPLACE FUNCTION app.current_groups()
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(current_setting('app.groups', true)::text[], '{}'::text[])
$$;

-- Returns the current clearance rank as integer, or 0 if not set.
CREATE OR REPLACE FUNCTION app.current_clearance_rank()
RETURNS integer
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(current_setting('app.clearance_rank', true)::integer, 0)
$$;

-- Returns the current allowed countries as text[], or empty array if not set.
CREATE OR REPLACE FUNCTION app.current_countries()
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(current_setting('app.countries', true)::text[], '{}'::text[])
$$;

-- Returns the current caveats as text[], or empty array if not set.
CREATE OR REPLACE FUNCTION app.current_caveats()
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(current_setting('app.caveats', true)::text[], '{}'::text[])
$$;

----------------------------------------------------------------------
-- Pattern 1: Ownership by username
--
-- Simplest RLS pattern. Each row has an owner, and only the owner
-- can see or modify it. btree index on the owner column.
----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS documents (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_username text NOT NULL,
  title text NOT NULL,
  body text NOT NULL
);

ALTER TABLE documents ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS documents_owner_username_idx
  ON documents (owner_username);

CREATE POLICY documents_select_own
  ON documents
  FOR SELECT
  USING (owner_username = app.current_username());

CREATE POLICY documents_insert_own
  ON documents
  FOR INSERT
  WITH CHECK (owner_username = app.current_username());

-- Explicit USING + WITH CHECK: target row must be owned by the user,
-- and the resulting row must still be owned by the user.
CREATE POLICY documents_update_own
  ON documents
  FOR UPDATE
  USING (owner_username = app.current_username())
  WITH CHECK (owner_username = app.current_username());

CREATE POLICY documents_delete_own
  ON documents
  FOR DELETE
  USING (owner_username = app.current_username());

----------------------------------------------------------------------
-- Pattern 2: Owner OR group overlap
--
-- Rows are visible to the owner or anyone in an overlapping group.
-- Uses text[] with GIN index for group matching via && (overlap).
-- Only owners can write.
----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS shared_docs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_username text NOT NULL,
  allowed_groups text[] NOT NULL DEFAULT '{}',
  title text NOT NULL,
  body text NOT NULL
);

ALTER TABLE shared_docs ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS shared_docs_owner_username_idx
  ON shared_docs (owner_username);

CREATE INDEX IF NOT EXISTS shared_docs_allowed_groups_gin
  ON shared_docs
  USING gin (allowed_groups);

-- Two permissive SELECT policies combine with OR:
-- owner can read, OR anyone in an overlapping group can read.
CREATE POLICY shared_docs_owner_read
  ON shared_docs
  FOR SELECT
  USING (owner_username = app.current_username());

CREATE POLICY shared_docs_group_read
  ON shared_docs
  FOR SELECT
  USING (allowed_groups && app.current_groups());

CREATE POLICY shared_docs_insert_own
  ON shared_docs
  FOR INSERT
  WITH CHECK (owner_username = app.current_username());

CREATE POLICY shared_docs_update_own
  ON shared_docs
  FOR UPDATE
  USING (owner_username = app.current_username())
  WITH CHECK (owner_username = app.current_username());

CREATE POLICY shared_docs_delete_own
  ON shared_docs
  FOR DELETE
  USING (owner_username = app.current_username());

----------------------------------------------------------------------
-- Pattern 3: Group match AND classification gate
--
-- Hot-path access-control attributes stored in typed columns.
-- Optional JSONB retained as source metadata envelope.
--
-- Two approaches shown:
--   A) Single policy with AND conjunction
--   B) Permissive grant path + restrictive safety gate
----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS classified_docs (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  owner_username text NOT NULL,
  allowed_groups text[] NOT NULL DEFAULT '{}',

  -- Typed columns for hot-path classification checks
  classification_level_rank integer NOT NULL,
  required_caveats text[] NOT NULL DEFAULT '{}',
  allowed_countries text[] NOT NULL DEFAULT '{}',

  -- Source metadata (not used in hot-path policy predicates)
  classification jsonb NOT NULL DEFAULT '{}'::jsonb,

  title text NOT NULL,
  body text NOT NULL
);

ALTER TABLE classified_docs ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS classified_docs_owner_username_idx
  ON classified_docs (owner_username);

CREATE INDEX IF NOT EXISTS classified_docs_level_idx
  ON classified_docs (classification_level_rank);

CREATE INDEX IF NOT EXISTS classified_docs_allowed_groups_gin
  ON classified_docs
  USING gin (allowed_groups);

CREATE INDEX IF NOT EXISTS classified_docs_required_caveats_gin
  ON classified_docs
  USING gin (required_caveats);

CREATE INDEX IF NOT EXISTS classified_docs_allowed_countries_gin
  ON classified_docs
  USING gin (allowed_countries);

-- Approach A: Single policy with AND conjunction
CREATE POLICY classified_docs_read
  ON classified_docs
  FOR SELECT
  USING (
    allowed_groups && app.current_groups()
    AND classification_level_rank <= app.current_clearance_rank()
    AND required_caveats <@ app.current_caveats()
    AND (
      allowed_countries = '{}'::text[]
      OR allowed_countries && app.current_countries()
    )
  );

-- Approach B: Separate permissive grant path + restrictive safety gate
-- (Uncomment to use instead of Approach A)
--
-- DROP POLICY IF EXISTS classified_docs_read ON classified_docs;
--
-- -- Permissive: grants access if user is in an allowed group
-- CREATE POLICY classified_docs_group_gate
--   ON classified_docs
--   AS PERMISSIVE
--   FOR SELECT
--   USING (allowed_groups && app.current_groups());
--
-- -- Restrictive: universal classification gate that must always pass
-- CREATE POLICY classified_docs_classification_gate
--   ON classified_docs
--   AS RESTRICTIVE
--   FOR SELECT
--   USING (
--     classification_level_rank <= app.current_clearance_rank()
--     AND required_caveats <@ app.current_caveats()
--     AND (
--       allowed_countries = '{}'::text[]
--       OR allowed_countries && app.current_countries()
--     )
--   );

-- Write policies: only owners can insert/update/delete.
--
-- NOTE: There is no owner-specific SELECT policy here. This is intentional.
-- In a classification-gated system, even document owners must pass the
-- classification gate to read (and therefore to UPDATE/DELETE) their own
-- rows. If an owner's clearance is revoked, they lose access to their own
-- documents. Because UPDATE and DELETE typically require SELECT rights
-- (for WHERE, RETURNING, SET expressions), owners who cannot pass the
-- classification-gated SELECT policy will also be unable to modify or
-- delete their own rows. If your use case requires owners to always
-- read/write their own rows regardless of classification, add a separate
-- permissive SELECT policy for owner_username = app.current_username().
CREATE POLICY classified_docs_insert_own
  ON classified_docs
  FOR INSERT
  WITH CHECK (owner_username = app.current_username());

CREATE POLICY classified_docs_update_own
  ON classified_docs
  FOR UPDATE
  USING (owner_username = app.current_username())
  WITH CHECK (owner_username = app.current_username());

CREATE POLICY classified_docs_delete_own
  ON classified_docs
  FOR DELETE
  USING (owner_username = app.current_username());

----------------------------------------------------------------------
-- Pattern 4: Server-side ownership population via trigger
--
-- Prevents clients from forging the owner_username column.
-- The trigger overwrites whatever the client sends.
----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION app.set_owner_username()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.owner_username := app.current_username();
  RETURN NEW;
END;
$$;

-- Apply to any table that needs server-enforced ownership:
-- CREATE TRIGGER documents_set_owner
--   BEFORE INSERT ON documents
--   FOR EACH ROW
--   EXECUTE FUNCTION app.set_owner_username();

----------------------------------------------------------------------
-- Pattern 5: initPlan optimization for row-independent lookups
--
-- When a policy calls a function or subquery whose result is constant
-- for the entire statement, wrapping it in (SELECT ...) encourages
-- the planner to evaluate it once as an initPlan rather than per-row.
----------------------------------------------------------------------

-- Instead of this (may evaluate per-row):
--   USING (owner_username = app.current_username())
--
-- Use this (encourages single evaluation):
--   USING (owner_username = (SELECT app.current_username()))
--
-- This is a planner hint, not a guarantee. Verify with EXPLAIN.

----------------------------------------------------------------------
-- Diagnostics
----------------------------------------------------------------------

-- Is RLS active in the current execution context?
-- SELECT row_security_active('public.classified_docs');

-- Recommended testing pattern:
-- BEGIN;
-- SET LOCAL ROLE app_user;
-- SET LOCAL app.username = 'alice';
-- SET LOCAL app.groups = '{"engineering","finance"}';
-- SET LOCAL app.clearance_rank = '2';
-- SET LOCAL app.countries = '{"US"}';
-- SET LOCAL app.caveats = '{"project-x"}';
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT *
-- FROM classified_docs
-- WHERE classification_level_rank <= 2
-- ORDER BY id
-- LIMIT 50;
--
-- ROLLBACK;
