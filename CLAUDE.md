# CLAUDE.md

## Project Overview

This is a personal repository for developing and maintaining coding assistant skills. Each skill is a self-contained directory with a `SKILL.md` file and optional supporting resources. Skills should be written to be agnostic to the coding assistant, supporting all three major vendors: Claude Code, Codex, and Gemini CLI. When differences between vendors can't be reconciled, prefer Claude Code conventions.

## Repository Layout

```
skills/
  skill-name/
    SKILL.md            # Required - YAML frontmatter + markdown instructions
    references/         # Optional - detailed reference material
    scripts/            # Optional - utility scripts
    resources/          # Optional - templates, data files
  another-skill/
    SKILL.md
    ...
```

## Developing Skills

### SKILL.md Requirements

- Must include YAML frontmatter with `name` and `description`
- `name`: lowercase letters, numbers, hyphens only (max 64 chars). No reserved words ("anthropic", "claude"). No XML tags.
- `description`: what the skill does AND when to use it (max 1024 chars). Written in third person. No XML tags.
- Body should be under 500 lines. Move detailed reference material to separate files.

### Naming Conventions

- Skill directory names use lowercase with hyphens: `my-skill-name/`
- Prefer gerund form (verb + -ing) or noun phrases: `processing-pdfs`, `pdf-processing`
- Avoid vague names (`helper`, `utils`) and overly generic names (`documents`, `data`)

### Writing Guidelines

- Be concise. Only add context the coding assistant does not already have.
- Use progressive disclosure: keep `SKILL.md` focused, put details in reference files.
- Keep reference file references one level deep from `SKILL.md`.
- Provide concrete examples with input/output pairs.
- Use consistent terminology throughout.
- Avoid time-sensitive information.

### Scripts

- Prefer utility scripts for deterministic operations.
- Scripts must handle errors explicitly.
- Document whether the coding assistant should execute vs. read the script.
- Use forward slashes in all file paths.
- Document any non-obvious values (no magic numbers).

### Testing

- Test skills with real usage scenarios before considering them ready.
- Develop iteratively: create in one session, test in another.

## Optional Frontmatter Fields

| Field | Description |
|---|---|
| `argument-hint` | Hint shown during autocomplete (e.g., `[issue-number]`) |
| `disable-model-invocation` | `true` to prevent auto-loading; user must invoke with `/name` |
| `user-invocable` | `false` to hide from the `/` menu (background knowledge only) |
| `allowed-tools` | Tools Claude can use without asking permission |
| `model` | Model to use when skill is active |
| `context` | `fork` to run in a forked subagent context |
| `agent` | Subagent type when `context: fork` is set |
