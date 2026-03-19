# Provider Comparison

Cross-provider reference for writing skills that target Claude Code, OpenAI Codex, and Gemini CLI. All three use the `SKILL.md` format with YAML frontmatter and share a common baseline through the Agent Skills open standard.

## The Agent Skills Open Standard

The [Agent Skills open standard](https://agentskills.io/specification) defines a shared skill format adopted by 30+ tools. Codex and Gemini CLI explicitly follow this standard. Claude Code's `SKILL.md` format aligns on core elements and extends it with provider-specific features.

The standard defines:
- `SKILL.md` with YAML frontmatter (`name`, `description`, `license`, `metadata`, `compatibility`, `allowed-tools`)
- Three optional subdirectories: `scripts/`, `references/`, `assets/`
- 3-level progressive disclosure: metadata → instructions → resources
- Name constraints: `^[a-z0-9-]+$`, max 64 chars, no leading/trailing/consecutive hyphens
- Description max: 1024 chars

## Common Baseline (All Three)

These features work identically across Claude Code, Codex, and Gemini CLI:

| Feature | Specification |
|---|---|
| Skill file | `SKILL.md` with YAML frontmatter between `---` fences |
| `name` field | Required. Max 64 chars. `^[a-z0-9-]+$`. Must match directory name. |
| `description` field | Required. Max 1024 chars. No XML tags. Third person. "What it does + when to use it." |
| Progressive disclosure | 3 levels: metadata (~100 tokens, always loaded) → body (on trigger) → resources (on demand). **Caveat:** Gemini CLI currently loads all resources at activation instead of on demand (see [issue #15895](https://github.com/google-gemini/gemini-cli/issues/15895)). |
| Body length | Under 500 lines recommended |
| `scripts/` subdirectory | Supported for executable code |
| User-level skills | Supported (paths differ per provider) |
| Project-level skills | Supported (paths differ per provider) |

## Frontmatter Field Comparison

| Field | Claude Code | Codex | Gemini CLI | Agent Skills Spec |
|---|---|---|---|---|
| `name` | Required | Required | Required | Required |
| `description` | Required | Required | Required | Required |
| `allowed-tools` | Supported | Supported | In spec (not processed) | Optional |
| `license` | Not recognized | Supported | In spec (not processed) | Optional |
| `metadata` | Not recognized | Supported (arbitrary object) | In spec (not processed) | Optional (string key-value) |
| `compatibility` | Not recognized | Not recognized | In spec (not processed) | Optional (max 500 chars) |
| `argument-hint` | Supported | Not recognized | Not recognized | Not in spec |
| `disable-model-invocation` | Supported | Not recognized | Not recognized | Not in spec |
| `user-invocable` | Supported | Not recognized | Not recognized | Not in spec |
| `model` | Supported | Not recognized | Not recognized | Not in spec |
| `context` | Supported (`fork`) | Not recognized | Not recognized | Not in spec |
| `agent` | Supported | Not recognized | Not recognized | Not in spec |
| `hooks` | Supported | Not recognized | Not recognized | Not in spec |

**Practical note:** Unrecognized fields are silently ignored by all three providers. Including Claude Code-specific fields like `argument-hint` does not break Codex or Gemini CLI — they simply skip them. Similarly, including `license` or `metadata` does not break Claude Code.

## Directory Conventions

| Subdirectory | Claude Code | Codex | Gemini CLI | Agent Skills Spec |
|---|---|---|---|---|
| `scripts/` | Supported | Supported | Supported | Defined |
| `resources/` | Supported | Not documented | Not documented | Not in spec |
| `references/` | Supported | Recommended | In spec | Defined |
| `assets/` | Not documented | Supported | In spec | Defined |
| `agents/` | Not documented | `agents/openai.yaml` | Not documented | Not in spec |

### `references/` subdirectory

The Agent Skills spec and Codex recommend a `references/` subdirectory for on-demand documentation files. Claude Code does not prescribe a specific directory structure but supports `references/` without issue. This repository uses `references/` as the standard convention, consistent with the Agent Skills spec.

In `SKILL.md`, prefix the path when referencing files (e.g., "read `references/reference.md`").

### Codex `agents/openai.yaml`

Codex supports an optional `agents/openai.yaml` file for UI metadata and invocation policy. This file is Codex-specific and ignored by other providers.

```yaml
interface:
  display_name: "My Skill"
  short_description: "Brief UI description"  # 25-64 chars
  icon_small: "./assets/icon.svg"
  icon_large: "./assets/icon.png"
  brand_color: "#3B82F6"
  default_prompt: "Example prompt mentioning $skill-name"

policy:
  allow_implicit_invocation: true  # default; false requires explicit $skillname

dependencies:
  tools:
    - type: "mcp"
      value: "tool-identifier"
      description: "What this tool provides"
      transport: "stdio"
      url: "mcp-server-endpoint"
```

## Skill Discovery Paths

| Scope | Claude Code | Codex | Gemini CLI |
|---|---|---|---|
| User-level | `~/.claude/skills/` | `~/.codex/skills/` or `~/.agents/skills/` | `~/.gemini/skills/` or `~/.agents/skills/` |
| Project-level | `.claude/skills/` | `.codex/skills/` or `.agents/skills/` | `.gemini/skills/` or `.agents/skills/` |
| System-wide | Not supported | `/etc/codex/skills/` | Not supported |
| Extensions | Plugin skills | Not supported | `~/.gemini/extensions/<name>/skills/` |
| Nested project | Subdirectory `.claude/skills/` | Parent `.agents/skills/` | Not documented |

### Multi-provider installation

To install a skill for all three providers, copy the skill directory to each provider's path:

```bash
cp -r ./my-skill ~/.claude/skills/my-skill
cp -r ./my-skill ~/.codex/skills/my-skill    # or ~/.agents/skills/my-skill
cp -r ./my-skill ~/.gemini/skills/my-skill   # or ~/.agents/skills/my-skill
```

Codex and Gemini CLI both recognize `.agents/skills/` as a shared alias, so a single copy there serves both.

## Provider-Specific Features

### Claude Code extensions

Features unique to Claude Code that have no equivalent in Codex or Gemini CLI:

| Feature | Description |
|---|---|
| `argument-hint` | Autocomplete hint shown after `/name` in the UI |
| `disable-model-invocation` | Prevents auto-loading; user must invoke with `/name` |
| `user-invocable: false` | Hides from `/` menu; Claude can still auto-load |
| `model` | Override the model when skill is active |
| `context: fork` + `agent` | Run skill in an isolated subagent (Explore, Plan, general-purpose, or custom) |
| `hooks` | Lifecycle hooks scoped to the skill's active period |
| `` !`command` `` | Shell preprocessing — command output replaces placeholder before Claude sees it |
| `$ARGUMENTS`, `$1`..`$N` | Argument substitution variables |
| `${CLAUDE_SESSION_ID}` | Current session ID variable |
| `${CLAUDE_SKILL_DIR}` | Directory containing the skill's `SKILL.md` |
| `ultrathink` keyword | Enables extended thinking when present in skill content |

### Codex extensions

| Feature | Description |
|---|---|
| `agents/openai.yaml` | UI metadata (`interface`), invocation policy (`policy`), MCP dependencies (`dependencies`) |
| `license` frontmatter | Per-skill license declaration |
| `metadata` frontmatter | Arbitrary structured metadata (e.g., `category`, `version`) |
| `$skillname` | Explicit invocation syntax (no slash prefix) |
| `/etc/codex/skills/` | System-wide admin-managed skills |

### Gemini CLI extensions

| Feature | Description |
|---|---|
| `.agents/skills/` alias | Shared alias recognized alongside `.gemini/skills/` (takes precedence) |
| Extension system | Skills bundled with MCP servers, context files, and custom commands |
| `compatibility` frontmatter | Environment requirements (in spec, not yet processed) |
| Custom commands | TOML-based prompt templates in `.gemini/commands/` (separate from skills) |
| Subagents | Specialized agents in `.gemini/agents/` (separate from skills) |
| `GEMINI.md` context files | Always-loaded project context with `@file.md` import syntax |

## Writing Cross-Provider Skills

When writing a skill intended for all three providers:

1. **Use only common frontmatter for portability.** `name` and `description` are the only fields processed by all three providers. `allowed-tools` is supported by Claude Code and Codex but not yet processed by Gemini CLI. Add provider-specific fields (like `argument-hint`) freely — unrecognized fields are silently ignored.

2. **Keep reference files one level deep from SKILL.md.** All three providers support this. Whether you use flat files or a `references/` subdirectory, the skill works everywhere.

3. **Do not depend on provider-specific features in core logic.** Features like `context: fork`, `` !`command` ``, and `hooks` only work in Claude Code. Use them as enhancements, not requirements.

4. **Prefer `scripts/` for executable code.** This is the one subdirectory recognized by all three providers.

5. **Test in all target providers.** Progressive disclosure behavior varies: Codex and Claude Code load resources on demand; Gemini CLI currently dumps all resources at activation time (per [issue #15895](https://github.com/google-gemini/gemini-cli/issues/15895)).

## Current Implementation Gaps

| Provider | Known gap |
|---|---|
| Gemini CLI | Only validates `name` and `description`; ignores `compatibility`, `allowed-tools`, `metadata` |
| Gemini CLI | Dumps all resources at activation instead of progressive on-demand loading |
| Gemini CLI | No semantic distinction between `scripts/`, `references/`, and `assets/` directories |
| Codex | `allowed-tools` behavior may differ from Claude Code's glob-matching implementation |
