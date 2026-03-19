---
name: writing-skills
description: Guides creation and improvement of coding assistant skills targeting
  Claude Code, OpenAI Codex, and Gemini CLI. Use when creating a new skill,
  editing an existing skill, reviewing skill quality, or scaffolding a skill
  directory. Covers SKILL.md authoring, frontmatter, progressive disclosure,
  cross-provider compatibility, descriptions, and validation.
---

# Writing Skills

A meta-skill for creating effective coding assistant skills that work across Claude Code, OpenAI Codex, and Gemini CLI. Built from patterns observed across 40+ skills in the Anthropic official repo, community projects, and security-focused skill sets. All three providers use the `SKILL.md` format with YAML frontmatter through the Agent Skills open standard.

## Core Principles

1. **Conciseness** - Only teach Claude what it doesn't already know. Every line should earn its place.
2. **Progressive disclosure** - Keep SKILL.md focused; move depth into reference files loaded on demand.
3. **Opinionated defaults** - Provide one clear path. Alternatives go in reference files, not the main body.

## Quick Reference: Frontmatter

Every `SKILL.md` begins with YAML frontmatter between `---` fences.

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Lowercase, hyphens, numbers only. Max 64 chars. |
| `description` | Yes | What it does + when to use it. Max 1024 chars. Third person. |
| `allowed-tools` | No | Tools the assistant can use without asking permission (Claude Code, Codex) |
| `argument-hint` | No | Autocomplete hint (e.g., `[issue-number]`) — Claude Code only |
| `disable-model-invocation` | No | `true` = only loads via `/name` — Claude Code only |
| `user-invocable` | No | `false` = hidden from `/` menu (background knowledge) — Claude Code only |
| `model` | No | Model override when skill is active — Claude Code only |
| `context` | No | `fork` to run in a forked subagent context — Claude Code only |
| `agent` | No | Subagent type when `context: fork` is set — Claude Code only |

For full field reference including types, defaults, constraints, string substitution variables, and decision tables, read `references/frontmatter.md`.

## Skill Creation Workflow

### Step 1: Define Purpose

Answer this question before writing anything:

> "What does this skill teach the assistant that it doesn't already know?"

If the answer is "nothing" or "general knowledge," you don't need a skill. Skills encode:
- Domain-specific workflows with ordered steps
- Project conventions the assistant can't infer from code alone
- Reference data (API schemas, config formats, checklists)
- Tool orchestration patterns for specific tasks

### Step 2: Scaffold the Directory

Run the init script to create a well-structured starting point:

```bash
bash writing-skills/scripts/init.sh my-skill-name
bash writing-skills/scripts/init.sh my-skill-name --with-scripts --with-references
```

This creates the directory, a SKILL.md template with frontmatter, and optionally `scripts/`, `references/`, and `resources/` subdirectories.

### Step 3: Write the Description

Use this formula:

```
[What it does — action verbs, third person]. Use when [trigger conditions].
```

**Good examples:**
```yaml
description: Generates and validates database migration files for PostgreSQL.
  Use when creating, modifying, or rolling back database schema changes.
```
```yaml
description: Enforces commit message conventions and runs pre-commit checks.
  Use when committing code, amending commits, or reviewing commit history.
```

**Bad examples:**
```yaml
# Too vague — doesn't say when to trigger
description: Helps with database stuff.

# First person — should be third person
description: I help you write better commit messages.

# No trigger conditions — Claude won't know when to load it
description: A comprehensive tool for managing all aspects of deployment.
```

Rules:
- Max 1024 characters
- Third person ("Generates...", "Validates...", not "Generate...", "I validate...")
- No XML tags anywhere in the description
- First sentence = what it does. Second sentence = when to use it.
- Be specific about trigger conditions so Claude loads the skill at the right time

### Step 4: Write the Body

First, identify your skill type:

| Type | When to use | Structure |
|---|---|---|
| **Workflow** | Multi-step processes with a defined order | Numbered steps, decision points, validation gates |
| **Reference** | Lookup information (APIs, configs, formats) | Tables, categorized sections, examples |
| **Technique** | Teaching a specific approach or pattern | Principles, examples, anti-patterns |

Then follow these writing principles:

- **Lead with action.** Start sections with what to do, not background context.
- **Use tables for structured data.** Tables are denser and scannable; prefer them over prose lists for field definitions, option comparisons, and mappings.
- **Show, don't tell.** A concrete example teaches more than a paragraph of explanation. Pair good examples with bad examples when the distinction matters.
- **One instruction per bullet.** Split compound instructions into separate items.
- **Use imperative mood.** "Run the script" not "You should run the script."
- **Define degrees of freedom.** Make clear what's fixed (must do) vs. flexible (can customize). Use "must", "should", "may" deliberately.

Keep the body under 500 lines. If it grows beyond that, extract reference material into separate files.

### Step 5: Validate and Test

Run the validation script:

```bash
bash writing-skills/scripts/validate.sh writing-skills
```

This checks frontmatter format, name constraints, description quality, body length, and common structural issues.

Then test in a fresh session for each target provider:
1. Open a new session (no prior context) in Claude Code, Codex, or Gemini CLI
2. Give a prompt that should trigger the skill
3. Verify the assistant discovers the skill, loads it, and follows the instructions
4. Check that reference files are loaded only when needed
5. If targeting multiple providers, repeat in each one — progressive disclosure and frontmatter handling differ across providers (see `references/provider-comparison.md`)

## Progressive Disclosure

Skills use a 3-level architecture:

| Level | What | Token cost | When loaded |
|---|---|---|---|
| **Metadata** | `name` + `description` from frontmatter | ~100 tokens | Always (Claude sees this to decide whether to load the skill) |
| **Instructions** | Body of `SKILL.md` | Varies | When Claude determines the skill is relevant |
| **Resources** | Reference files, scripts, templates | Varies | When explicitly referenced by instructions |

### When to Split Content

Move content out of `SKILL.md` into a reference file when:
- It's detailed reference data that most invocations won't need (field specs, API schemas)
- It's a collection of examples that would bloat the main flow
- It's a checklist or template meant to be used as-is
- The body exceeds ~300 lines and some sections are situational

### Rules for Reference Files

- **One level deep.** SKILL.md can reference `references/patterns.md`. `references/patterns.md` must not reference `other-patterns.md`. This prevents Claude from chasing a chain of files.
- **Self-contained sections.** Each reference file should be useful on its own without requiring the reader to jump back to SKILL.md.
- **Clear loading triggers.** In SKILL.md, state exactly when to load each reference file (e.g., "For anti-pattern details, read `references/patterns.md`").
- **Use `Read` tool to load files.** Instruct Claude to use the Read tool for reference files. Do not inline large reference content in SKILL.md.

## Scripts and Resources

### When to Use Each

| Asset | Use when |
|---|---|
| **Script** | The operation is deterministic, repetitive, or error-prone if done manually (scaffolding, validation, formatting) |
| **Reference file** | The content is informational and Claude needs to reason about it (patterns, guidelines, checklists) |
| **Resource file** | The content is a template or data file used as-is (config templates, schema files) |

### Script Conventions

- Use bash. Keep dependencies minimal (standard Unix tools).
- Handle errors explicitly: validate inputs, check file existence, use `set -euo pipefail`.
- Use forward slashes in all file paths.
- Document non-obvious values with comments (no magic numbers).
- Print descriptive error messages and exit non-zero on failure.
- Document in SKILL.md whether Claude should **execute** the script or **read** it.

## Common Pitfalls

Avoid these anti-patterns when writing skills:

1. **Verbose descriptions** - Descriptions over ~200 characters often contain unnecessary context. Tighten to action + trigger.
2. **Missing trigger conditions** - A description without "Use when..." leaves Claude guessing when to load the skill.
3. **Nested references** - Reference file A links to reference file B. Keep references one level deep from SKILL.md.
4. **Option overload** - Presenting 5 ways to do something when 1 good default suffices. Be opinionated in SKILL.md; put alternatives in reference files.
5. **Narrative style** - Writing prose paragraphs instead of structured instructions. Use bullets, tables, and code blocks.
6. **Teaching common knowledge** - Explaining git basics or standard language features Claude already knows. Only add what's specific to your workflow.
7. **Overlong body** - SKILL.md over 500 lines. Split into reference files.
8. **Magic values** - Hardcoded numbers or strings without explanation. Add comments or constants.
9. **Backslash paths** - Using `\` in file paths. Always use forward slashes `/`.
10. **Missing error handling in scripts** - Scripts that silently fail. Always validate inputs and exit non-zero on errors.
11. **Vague section headers** - Headers like "Notes" or "Other." Use specific, descriptive headers.
12. **Time-sensitive content** - Referencing specific versions, dates, or "current" behavior that will become stale.

For detailed pattern and anti-pattern examples with code, read `references/patterns.md`.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/frontmatter.md` | Complete frontmatter field reference with types, defaults, constraints, string substitution variables, and decision table | Writing or debugging frontmatter fields beyond the quick reference table above |
| `references/provider-comparison.md` | Cross-provider comparison of Claude Code, Codex, and Gemini CLI: frontmatter fields, directory conventions, discovery paths, provider-specific features, and the Agent Skills open standard | Writing skills that target multiple providers, understanding which features are portable vs. provider-specific, or configuring provider-specific extensions like Codex `agents/openai.yaml` |
| `references/patterns.md` | Content organization patterns, workflow patterns, output patterns, and anti-patterns with examples | Designing skill structure, reviewing skill quality, or encountering an unfamiliar pattern |
| `references/checklist.md` | Pre-flight validation checklist (copyable markdown) | Final review before considering a skill ready |

## Utility Scripts

| Script | Purpose | Execute or Read |
|---|---|---|
| `scripts/init.sh` | Scaffold a new skill directory with SKILL.md template | **Execute**: `bash writing-skills/scripts/init.sh <skill-name> [--with-scripts] [--with-references] [--with-resources]` |
| `scripts/validate.sh` | Validate SKILL.md structure and content | **Execute**: `bash writing-skills/scripts/validate.sh <skill-directory>` |
