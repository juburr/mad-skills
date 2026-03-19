# Pre-Flight Checklist

Use this checklist before considering a skill ready. Copy into your review notes and check each item.

## Frontmatter

- [ ] `name` is lowercase, hyphens, and numbers only
- [ ] `name` is 64 characters or fewer
- [ ] `name` does not contain reserved words (`anthropic`, `claude`)
- [ ] `description` is present and non-empty
- [ ] `description` is 1024 characters or fewer
- [ ] `description` is written in third person ("Generates...", not "Generate...")
- [ ] `description` includes trigger conditions ("Use when...")
- [ ] `description` contains no XML tags
- [ ] `name` contains no XML tags
- [ ] Optional fields are only included if actually needed

## Content Quality

- [ ] Every section teaches Claude something it doesn't already know
- [ ] Instructions use imperative mood ("Run the script", not "You should run the script")
- [ ] Each bullet contains a single instruction (no compound bullets)
- [ ] Tables used for structured data instead of prose lists
- [ ] Concrete examples included for non-obvious behaviors
- [ ] Good/bad example pairs used where the distinction matters
- [ ] No passive voice in instructions
- [ ] No time-sensitive information (version numbers, dates, "currently")
- [ ] Consistent terminology throughout (same term for same concept)
- [ ] Section headers are specific and descriptive (not "Notes" or "Other")

## Progressive Disclosure

- [ ] SKILL.md body is under 500 lines
- [ ] Reference files are only one level deep (no chained references)
- [ ] Each reference file is self-contained
- [ ] SKILL.md states when to load each reference file
- [ ] Detailed reference data lives in reference files, not SKILL.md

## Workflow Skills

- [ ] Steps are numbered and ordered
- [ ] Decision points have clear conditions and branches
- [ ] Validation/checkpoint gates are marked where needed
- [ ] Degrees of freedom are explicit (must/should/may)

## Scripts

- [ ] Scripts use `set -euo pipefail`
- [ ] All inputs are validated
- [ ] Error messages are descriptive
- [ ] Exit codes are non-zero on failure
- [ ] File paths use forward slashes only
- [ ] No magic numbers (constants are named and commented)
- [ ] SKILL.md documents whether to execute or read each script

## Testing

- [ ] Ran `validate.sh` with 0 errors
- [ ] Tested in a fresh session for each target provider (no prior context)
- [ ] Skill loads when expected trigger conditions are met
- [ ] Skill does NOT load for unrelated prompts
- [ ] Reference files load only when needed
- [ ] Scripts execute successfully
