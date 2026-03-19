#!/usr/bin/env bash
# Scaffold a new skill directory with a SKILL.md template.
#
# Usage:
#   bash writing-skills/scripts/init.sh <skill-name> [--with-scripts] [--with-references] [--with-resources]
#
# Arguments:
#   skill-name         Required. Kebab-case name for the skill (e.g., my-skill-name).
#   --with-scripts     Optional. Create a scripts/ subdirectory.
#   --with-references  Optional. Create a references/ subdirectory.
#   --with-resources   Optional. Create a resources/ subdirectory.

set -euo pipefail

# --- Constants -----------------------------------------------------------
MAX_NAME_LENGTH=64           # Claude Code frontmatter constraint
NAME_PATTERN='^[a-z0-9-]+$' # Allowed characters in skill names
RESERVED_WORDS="anthropic claude"

# --- Functions ------------------------------------------------------------
die() {
    echo "Error: $1" >&2
    exit 1
}

usage() {
    echo "Usage: bash writing-skills/scripts/init.sh <skill-name> [--with-scripts] [--with-references] [--with-resources]"
    exit 1
}

# --- Parse arguments ------------------------------------------------------
if [ $# -lt 1 ]; then
    usage
fi

SKILL_NAME="$1"
shift

WITH_SCRIPTS=false
WITH_REFERENCES=false
WITH_RESOURCES=false

while [ $# -gt 0 ]; do
    case "$1" in
        --with-scripts)
            WITH_SCRIPTS=true
            ;;
        --with-references)
            WITH_REFERENCES=true
            ;;
        --with-resources)
            WITH_RESOURCES=true
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
    shift
done

# --- Validate skill name --------------------------------------------------
if [ -z "$SKILL_NAME" ]; then
    die "Skill name is required."
fi

if ! echo "$SKILL_NAME" | grep -qE "$NAME_PATTERN"; then
    die "Skill name '$SKILL_NAME' must contain only lowercase letters, numbers, and hyphens."
fi

if [ ${#SKILL_NAME} -gt $MAX_NAME_LENGTH ]; then
    die "Skill name '$SKILL_NAME' exceeds $MAX_NAME_LENGTH character limit (${#SKILL_NAME} chars)."
fi

for word in $RESERVED_WORDS; do
    if echo "$SKILL_NAME" | grep -qi "$word"; then
        die "Skill name '$SKILL_NAME' contains reserved word '$word'."
    fi
done

if [ -d "$SKILL_NAME" ]; then
    die "Directory '$SKILL_NAME' already exists."
fi

# --- Create directory structure -------------------------------------------
echo "Creating skill: $SKILL_NAME"

mkdir -p "$SKILL_NAME"

if [ "$WITH_SCRIPTS" = true ]; then
    mkdir -p "$SKILL_NAME/scripts"
    echo "  Created $SKILL_NAME/scripts/"
fi

if [ "$WITH_REFERENCES" = true ]; then
    mkdir -p "$SKILL_NAME/references"
    echo "  Created $SKILL_NAME/references/"
fi

if [ "$WITH_RESOURCES" = true ]; then
    mkdir -p "$SKILL_NAME/resources"
    echo "  Created $SKILL_NAME/resources/"
fi

# --- Generate SKILL.md template ------------------------------------------
cat > "$SKILL_NAME/SKILL.md" << 'TEMPLATE'
---
name: SKILL_NAME_PLACEHOLDER
description: TODO - What this skill does (action verbs, third person). Use when
  TODO - trigger conditions.
---

# TODO: Skill Title

## Overview

TODO: Brief description of what this skill does and why it exists.

## Workflow

1. TODO: First step
2. TODO: Second step
3. TODO: Third step
TEMPLATE

# Replace placeholder with actual skill name
sed -i "s/SKILL_NAME_PLACEHOLDER/$SKILL_NAME/" "$SKILL_NAME/SKILL.md"

echo "  Created $SKILL_NAME/SKILL.md"
echo ""
echo "Done. Next steps:"
echo "  1. Edit $SKILL_NAME/SKILL.md — fill in the description and body"
echo "  2. Run: bash writing-skills/scripts/validate.sh $SKILL_NAME"
