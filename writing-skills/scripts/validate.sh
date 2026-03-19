#!/usr/bin/env bash
# Validate a skill's SKILL.md structure and content.
#
# Usage:
#   bash writing-skills/scripts/validate.sh <skill-directory>
#
# Checks:
#   - SKILL.md exists
#   - Frontmatter present and well-formed
#   - Name format, length, and reserved words
#   - Description present, length, and XML tags
#   - Body line count (warn if >500)
#   - Nested reference heuristic
#   - Backslash paths
#
# Exit: 0 if no errors (warnings OK), 1 if any errors.

set -euo pipefail

# --- Constants -----------------------------------------------------------
MAX_NAME_LENGTH=64             # Claude Code frontmatter constraint
MAX_DESCRIPTION_LENGTH=1024    # Claude Code frontmatter constraint
MAX_BODY_LINES=500             # Recommended max for SKILL.md body
NAME_PATTERN='^[a-z0-9-]+$'   # Allowed characters in skill names
RESERVED_WORDS="anthropic claude"

# --- Functions ------------------------------------------------------------
ERRORS=0
WARNINGS=0

pass() {
    echo "  [PASS] $1"
}

fail() {
    echo "  [FAIL] $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo "  [WARN] $1"
    WARNINGS=$((WARNINGS + 1))
}

die() {
    echo "Error: $1" >&2
    exit 1
}

# --- Parse arguments ------------------------------------------------------
if [ $# -lt 1 ]; then
    echo "Usage: bash writing-skills/scripts/validate.sh <skill-directory>"
    exit 1
fi

SKILL_DIR="$1"

# --- Check SKILL.md exists ------------------------------------------------
SKILL_FILE="$SKILL_DIR/SKILL.md"
echo "Validating: $SKILL_FILE"
echo ""

if [ ! -f "$SKILL_FILE" ]; then
    die "SKILL.md not found at $SKILL_FILE"
fi

pass "SKILL.md exists"

# --- Read file content ----------------------------------------------------
CONTENT=$(cat "$SKILL_FILE")

# --- Check frontmatter exists ---------------------------------------------
if echo "$CONTENT" | head -n 1 | grep -q '^---$'; then
    # Find closing fence (second occurrence of ---)
    CLOSE_LINE=$(echo "$CONTENT" | tail -n +2 | grep -n '^---$' | head -n 1 | cut -d: -f1)
    if [ -n "$CLOSE_LINE" ]; then
        pass "Frontmatter delimiters present"
        # Extract frontmatter (between the two --- lines)
        FRONTMATTER=$(echo "$CONTENT" | sed -n "2,$((CLOSE_LINE))p")
        BODY_START=$((CLOSE_LINE + 2))
    else
        fail "Frontmatter opening '---' found but no closing '---'"
        FRONTMATTER=""
        BODY_START=1
    fi
else
    fail "No frontmatter found (file must start with '---')"
    FRONTMATTER=""
    BODY_START=1
fi

# --- Validate name --------------------------------------------------------
NAME=$(echo "$FRONTMATTER" | grep '^name:' | head -n 1 | sed 's/^name:[[:space:]]*//')

if [ -z "$NAME" ]; then
    fail "name field is missing from frontmatter"
else
    pass "name field present: '$NAME'"

    # Check format
    if echo "$NAME" | grep -qE "$NAME_PATTERN"; then
        pass "name format valid (lowercase, hyphens, numbers)"
    else
        fail "name '$NAME' contains invalid characters (allowed: lowercase letters, numbers, hyphens)"
    fi

    # Check length
    if [ ${#NAME} -le $MAX_NAME_LENGTH ]; then
        pass "name length OK (${#NAME}/$MAX_NAME_LENGTH chars)"
    else
        fail "name exceeds $MAX_NAME_LENGTH chars (${#NAME} chars)"
    fi

    # Check reserved words
    RESERVED_FOUND=false
    for word in $RESERVED_WORDS; do
        if echo "$NAME" | grep -qi "$word"; then
            fail "name contains reserved word '$word'"
            RESERVED_FOUND=true
        fi
    done
    if [ "$RESERVED_FOUND" = false ]; then
        pass "name does not contain reserved words"
    fi

    # Check XML tags
    if echo "$NAME" | grep -qE '<[^>]+>'; then
        fail "name contains XML tags"
    else
        pass "name contains no XML tags"
    fi
fi

# --- Validate description -------------------------------------------------
# Description may span multiple lines in YAML (folded scalar)
# Extract everything after "description:" until the next top-level field or end of frontmatter
DESCRIPTION=$(echo "$FRONTMATTER" | sed -n '/^description:/,/^[a-z]/p' | sed '$ { /^[a-z]/{ /^description:/!d } }' | sed 's/^description:[[:space:]]*//' | tr '\n' ' ' | sed 's/[[:space:]]*$//')

if [ -z "$DESCRIPTION" ]; then
    fail "description field is missing from frontmatter"
else
    pass "description field present"

    # Check length
    DESC_LENGTH=${#DESCRIPTION}
    if [ $DESC_LENGTH -le $MAX_DESCRIPTION_LENGTH ]; then
        pass "description length OK ($DESC_LENGTH/$MAX_DESCRIPTION_LENGTH chars)"
    else
        fail "description exceeds $MAX_DESCRIPTION_LENGTH chars ($DESC_LENGTH chars)"
    fi

    # Check for XML tags
    if echo "$DESCRIPTION" | grep -qE '<[^>]+>'; then
        fail "description contains XML tags"
    else
        pass "description contains no XML tags"
    fi

    # Check for trigger conditions
    if echo "$DESCRIPTION" | grep -qi "use when"; then
        pass "description includes trigger conditions ('Use when')"
    else
        warn "description missing trigger conditions (recommended: 'Use when ...')"
    fi
fi

# --- Validate body --------------------------------------------------------
TOTAL_LINES=$(echo "$CONTENT" | wc -l)
BODY_LINES=$((TOTAL_LINES - BODY_START + 1))

if [ $BODY_LINES -le $MAX_BODY_LINES ]; then
    pass "body length OK ($BODY_LINES/$MAX_BODY_LINES lines)"
else
    warn "body exceeds recommended $MAX_BODY_LINES lines ($BODY_LINES lines) — consider splitting into reference files"
fi

# --- Check for nested references ------------------------------------------
# Heuristic: look for "read `filename.md`" patterns in non-SKILL.md files
NESTED_REFS=0
if [ -d "$SKILL_DIR" ]; then
    for ref_file in "$SKILL_DIR"/*.md; do
        # Skip SKILL.md itself
        if [ "$(basename "$ref_file")" = "SKILL.md" ]; then
            continue
        fi
        if [ -f "$ref_file" ]; then
            # Look for patterns like "read `file.md`" or "Read file.md"
            if grep -qiE '(read|load|see|refer to)[[:space:]]+`?[a-z0-9_-]+\.md' "$ref_file" 2>/dev/null; then
                warn "$(basename "$ref_file") may contain nested references (references should be one level deep)"
                NESTED_REFS=$((NESTED_REFS + 1))
            fi
        fi
    done
    if [ $NESTED_REFS -eq 0 ]; then
        pass "no nested references detected in reference files"
    fi
fi

# --- Check for backslash paths --------------------------------------------
if grep -qE '\\\\' "$SKILL_FILE" 2>/dev/null; then
    warn "SKILL.md contains backslash characters (use forward slashes for file paths)"
else
    pass "no backslash paths detected"
fi

# --- Summary --------------------------------------------------------------
echo ""
echo "---"
echo "Results: $ERRORS error(s), $WARNINGS warning(s)"

if [ $ERRORS -gt 0 ]; then
    echo "Status: FAILED"
    exit 1
else
    if [ $WARNINGS -gt 0 ]; then
        echo "Status: PASSED with warnings"
    else
        echo "Status: PASSED"
    fi
    exit 0
fi
