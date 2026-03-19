# Patterns and Anti-Patterns

Recurring structural patterns observed across effective Claude Code skills, plus common anti-patterns to avoid.

## Content Organization Patterns

### Self-Contained

Everything in a single SKILL.md. No reference files.

**When to use:** Simple skills under ~150 lines. The skill is a single workflow or a compact reference.

```
skill-name/
  SKILL.md    # Everything lives here
```

### Guide with References

Concise SKILL.md links to reference files for depth.

**When to use:** The skill has a clear primary workflow but needs detailed reference data, extensive examples, or checklists that would bloat the main file.

```
skill-name/
  SKILL.md           # Workflow + summaries (~200-300 lines)
  reference.md       # Detailed field/API reference
  examples.md        # Extended examples
  checklist.md       # Validation checklist
```

### Domain-Specific

SKILL.md focuses on a single domain with specialized terminology and conventions.

**When to use:** The skill targets a specific technology, framework, or domain (e.g., Kubernetes, PostgreSQL, React Native).

Key traits:
- Defines domain terminology upfront
- References official documentation URLs
- Includes domain-specific validation rules

### Conditional / Multi-Path

SKILL.md routes to different instructions based on context.

**When to use:** The skill handles multiple related tasks that share setup but diverge in execution.

```markdown
## Determine Task Type

Based on the user's request:
- **Creating a new migration** → follow "Create Migration" below
- **Rolling back** → follow "Rollback" below
- **Validating existing migrations** → follow "Validate" below
```

## Workflow Patterns

### Sequential

Steps executed in a fixed order. Most common pattern.

```markdown
## Workflow

1. Read the configuration file
2. Validate required fields
3. Generate output
4. Run validation script
```

### Decision Tree

Branch based on conditions discovered during execution.

```markdown
## Workflow

1. Check if `package.json` exists
   - **Yes** → Read dependencies, continue to step 2
   - **No** → Ask user to initialize project, stop
2. Check framework
   - **React** → Follow React setup
   - **Vue** → Follow Vue setup
   - **Other** → Follow generic setup
```

### Feedback Loop

Iterate until a quality bar is met.

```markdown
## Workflow

1. Generate initial output
2. Run validation script
3. If validation fails:
   - Read error output
   - Fix identified issues
   - Return to step 2
4. If validation passes, present result to user
```

### Gate / Checkpoint

Pause for user confirmation at critical points.

```markdown
## Workflow

1. Analyze codebase and propose changes
2. **Checkpoint:** Present plan to user. Wait for approval before continuing.
3. Implement approved changes
4. Run tests
5. **Checkpoint:** Show test results. Ask user to confirm before committing.
```

## Output Patterns

### Template (Strict)

Output must match an exact format. Use when generating config files, manifests, or formatted documents.

````markdown
## Output Format

Generate a migration file matching this template exactly:

```sql
-- Migration: $MIGRATION_NAME
-- Created: $TIMESTAMP

BEGIN;

$UP_SQL

COMMIT;
```
````

### Template (Flexible)

Output follows a general structure but allows variation. Use when generating code, documentation, or reports.

````markdown
## Output Structure

Generated components should follow this structure:

```tsx
// Imports (framework first, then local)
// Type definitions
// Component function
// Helper functions (if any)
// Default export
```
````

### Examples (Input/Output Pairs)

Show concrete transformations to define expected behavior.

````markdown
## Examples

**Input:** User asks to "add a created_at timestamp to users"

**Output:**
```sql
ALTER TABLE users ADD COLUMN created_at TIMESTAMP NOT NULL DEFAULT NOW();
```

**Input:** User asks to "remove the email column from orders"

**Output:**
```sql
ALTER TABLE orders DROP COLUMN email;
```
````

## Anti-Patterns

### 1. The Wall of Text

**Bad:**
```markdown
This skill helps you manage database migrations. Database migrations are a way
to version control your database schema. They allow you to make changes to your
database in a structured and repeatable way. When you create a migration, you
define the changes you want to make, and the migration system applies them in
order. This is important because...
```

**Why it fails:** Claude already knows what migrations are. This wastes tokens on common knowledge.

**Good:**
```markdown
## Create Migration

1. Generate a timestamped migration file in `db/migrations/`
2. Use the naming convention: `YYYYMMDDHHMMSS_description.sql`
3. Include both `UP` and `DOWN` sections
```

### 2. The Option Buffet

**Bad:**
```markdown
You can structure your description in several ways:
- Action-first: "Generates X. Use when Y."
- Trigger-first: "When Y happens, generates X."
- Capability list: "Handles A, B, and C for X."
- Question-based: "Answers questions about X."
- Hybrid: Combine any of the above.
```

**Why it fails:** Five options creates decision paralysis. Claude wastes time choosing instead of acting.

**Good:**
```markdown
Use this formula for descriptions:
`[What it does — action verbs]. Use when [trigger conditions].`
```

### 3. The Russian Doll

**Bad:**
```markdown
<!-- SKILL.md -->
For details, read `overview.md`.

<!-- overview.md -->
For field specifications, read `fields/required.md`.

<!-- fields/required.md -->
For name validation rules, read `fields/validation/name-rules.md`.
```

**Why it fails:** Each level of nesting costs a Read tool call and adds latency. Claude may lose context across hops.

**Good:** Keep references one level deep. SKILL.md links to reference files; reference files are self-contained.

### 4. The Passive Voice

**Bad:**
```markdown
The configuration file should be read first. Then the schema should be validated.
Output should be generated according to the template.
```

**Why it fails:** Passive voice is less direct and harder to follow as instructions.

**Good:**
```markdown
1. Read the configuration file
2. Validate the schema
3. Generate output using the template
```

### 5. The Unnecessary Wrapper

**Bad:**
```markdown
## Git Commit Workflow

1. Run `git add .`
2. Run `git commit -m "message"`
3. Run `git push`
```

**Why it fails:** Claude already knows how to use git. This skill adds no new knowledge.

**Good:** Only create skills for workflows with project-specific conventions, custom validation, or non-obvious steps.

### 6. The Kitchen Sink

**Bad:** A single SKILL.md that's 800 lines covering setup, development, testing, deployment, monitoring, and troubleshooting.

**Why it fails:** Most invocations only need one section. Loading everything wastes context.

**Good:** Either split into multiple focused skills, or use progressive disclosure with reference files.

### 7. The Stale Reference

**Bad:**
```markdown
Use React 18's `createRoot` API (as of React 18.2.0, released June 2022).
```

**Why it fails:** Version numbers and dates become incorrect. Claude may have newer knowledge.

**Good:**
```markdown
Use React's `createRoot` API for rendering.
```

### 8. The Invisible Trigger

**Bad:**
```yaml
description: A comprehensive database management toolkit with advanced features.
```

**Why it fails:** No trigger conditions. Claude doesn't know when to load it. "Comprehensive" and "advanced" are meaningless qualifiers.

**Good:**
```yaml
description: Generates and validates database migration files. Use when creating,
  modifying, or rolling back database schema changes.
```

### 9. The Compound Instruction

**Bad:**
```markdown
- Read the config file, validate the schema, and if there are errors, report them to the user with line numbers and suggestions for fixes.
```

**Why it fails:** Multiple instructions crammed into one bullet are easy to partially miss.

**Good:**
```markdown
- Read the config file
- Validate the schema
- If validation fails:
  - Report errors with line numbers
  - Suggest fixes for each error
```

### 10. The Magic Number

**Bad:**
```bash
if [ ${#name} -gt 64 ]; then
    echo "Name too long"
fi
sleep 3
head -n 500 "$file"
```

**Why it fails:** 64, 3, and 500 are unexplained. Future readers (including Claude) can't tell if they're arbitrary or meaningful.

**Good:**
```bash
MAX_NAME_LENGTH=64  # Claude Code frontmatter constraint
if [ ${#name} -gt $MAX_NAME_LENGTH ]; then
    echo "Name exceeds $MAX_NAME_LENGTH character limit"
fi
```
