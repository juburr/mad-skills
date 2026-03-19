# Frontmatter Reference

Complete reference for SKILL.md YAML frontmatter fields.

## Required Fields

### `name`

- **Type:** string
- **Constraints:** Lowercase letters, numbers, and hyphens only (`^[a-z0-9-]+$`). Max 64 characters. Must not contain reserved words: `anthropic`, `claude`.
- **No XML tags** anywhere in the value.

```yaml
# Good
name: writing-skills
name: pdf-processing
name: k8s-deploy

# Bad
name: Writing_Skills    # uppercase and underscores
name: my-claude-helper  # contains reserved word "claude"
name: a-very-long-skill-name-that-exceeds-the-sixty-four-character-maximum-limit  # too long
```

### `description`

- **Type:** string (can use YAML multi-line with folding)
- **Max length:** 1024 characters
- **Voice:** Third person ("Generates...", not "Generate..." or "I generate...")
- **Formula:** `[What it does — action verbs]. Use when [trigger conditions].`
- **No XML tags** anywhere in the value.

```yaml
# Single line
description: Generates database migration files. Use when creating or modifying schema.

# Multi-line (folded — newlines become spaces)
description: Generates and validates database migration files for PostgreSQL.
  Use when creating, modifying, or rolling back database schema changes.
  Supports up/down migrations and dry-run validation.
```

The description is always visible to Claude as metadata (~100 tokens). It determines whether Claude loads the full skill. Write trigger conditions precisely so the skill activates at the right time and stays dormant otherwise.

## Optional Fields

Fields below are supported by Claude Code unless otherwise noted. Unrecognized fields are silently ignored by other providers. For the full cross-provider field comparison, read `references/provider-comparison.md`.

### `argument-hint` (Claude Code only)

- **Type:** string
- **Default:** none
- **Purpose:** Shown in autocomplete after `/name` to hint at expected arguments.

```yaml
argument-hint: "[issue-number]"
argument-hint: "[file-path]"
argument-hint: "[component-name]"
```

### `disable-model-invocation` (Claude Code only)

- **Type:** boolean
- **Default:** `false`
- **Purpose:** When `true`, Claude will not auto-load this skill based on context. The user must explicitly invoke it with `/name`.

```yaml
disable-model-invocation: true
```

Use this for skills that are expensive to load, have side effects, or should only run when explicitly requested.

### `user-invocable` (Claude Code only)

- **Type:** boolean
- **Default:** `true`
- **Purpose:** When `false`, the skill is hidden from the `/` menu. Claude can still load it automatically based on context, but users can't invoke it directly.

```yaml
user-invocable: false
```

Use this for background knowledge skills that inform Claude's behavior without being a discrete action.

### `allowed-tools` (Claude Code, Codex)

- **Type:** list of strings
- **Default:** none
- **Purpose:** Tools Claude can use without asking the user for permission when this skill is active.

```yaml
allowed-tools:
  - Bash(git status)
  - Bash(git diff *)
  - Bash(npm test)
  - Read
  - Glob
  - Grep
```

Tool patterns support glob matching. `Bash(git diff *)` allows any `git diff` variant.

### `model` (Claude Code only)

- **Type:** string
- **Default:** inherits from session
- **Purpose:** Override the model used when this skill is active.

```yaml
model: claude-sonnet-4-6
```

Use sparingly. Most skills should work with whatever model the user has configured.

### `context` (Claude Code only)

- **Type:** string
- **Default:** none
- **Values:** `fork`
- **Purpose:** When set to `fork`, the skill runs in a forked subagent context isolated from the main conversation.

```yaml
context: fork
```

### `agent` (Claude Code only)

- **Type:** string
- **Default:** none
- **Purpose:** Specifies the subagent type when `context: fork` is set.

```yaml
context: fork
agent: plan
```

## String Substitution Variables (Claude Code only)

These variables are expanded at runtime inside skill content by Claude Code. Other providers do not currently support variable substitution.

| Variable | Expands to |
|---|---|
| `$ARGUMENTS` | Full argument string passed after `/name` |
| `$1`, `$2`, ... `$N` | Positional arguments (space-separated) |
| `${CLAUDE_SESSION_ID}` | Unique ID for the current Claude session |
| `` !`command` `` | Output of running a shell command at load time |

```yaml
# Example: skill that takes a PR number as argument
argument-hint: "[pr-number]"
---

Review PR #$1 using the following checklist...
```

```markdown
<!-- Dynamic content from shell command -->
Current git branch: !`git branch --show-current`
```

## Decision Table

Use this table to find the right field for your use case:

| I want to... | Use field |
|---|---|
| Show a hint for expected arguments | `argument-hint` |
| Prevent auto-loading, require explicit `/name` | `disable-model-invocation: true` |
| Hide from the `/` menu but allow auto-loading | `user-invocable: false` |
| Allow specific tools without permission prompts | `allowed-tools` |
| Force a specific model | `model` |
| Run in an isolated subagent | `context: fork` + `agent` |
| Pass user input into the skill body | `$ARGUMENTS`, `$1`, `$2`, etc. |
| Include dynamic runtime data | `` !`command` `` |
