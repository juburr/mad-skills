#!/usr/bin/env bash
# Uninstall skills that were installed from this repository.
#
# Removes skills from the skills directories for Claude Code, Codex, and
# Gemini CLI. Only skills whose names match a directory in this repository
# are removed. Skills installed from other sources are never touched.
#
# Usage:
#   bash uninstall.sh                            # Remove all skills provided by this repo
#   bash uninstall.sh <skill-name>               # Remove only the named skill
#   bash uninstall.sh --targets claude,codex      # Remove from specific assistants only
#
# Skills are directories containing a SKILL.md file at the top level of this
# repository. Hidden directories and files without SKILL.md are ignored.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECIFIC_SKILL=""
TARGETS_ARG=""

# Map of assistant name -> skills directory
declare -A ASSISTANT_DIRS=(
    [claude]="$HOME/.claude/skills"
    [codex]="$HOME/.codex/skills"
    [gemini]="$HOME/.gemini/skills"
)

# --- Parse arguments ------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --targets)
            if [ $# -lt 2 ]; then
                echo "Error: --targets requires a value (e.g., --targets claude,codex)" >&2
                exit 1
            fi
            TARGETS_ARG="$2"
            shift
            ;;
        -h|--help)
            echo "Usage: bash uninstall.sh [skill-name] [--targets LIST]"
            echo ""
            echo "Arguments:"
            echo "  <skill-name>  Remove only the named skill (optional)"
            echo ""
            echo "Options:"
            echo "  --targets <list>  Comma-separated list of coding assistants to remove from"
            echo "                    Valid values: claude, codex, gemini, all (default: all)"
            echo "  -h, --help        Show this help message"
            echo ""
            echo "Only skills whose names match directories in this repository"
            echo "are removed. Other skills are never touched."
            exit 0
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            echo "Run 'bash uninstall.sh --help' for usage." >&2
            exit 1
            ;;
        *)
            if [ -n "$SPECIFIC_SKILL" ]; then
                echo "Error: Only one skill name may be specified." >&2
                echo "Run 'bash uninstall.sh --help' for usage." >&2
                exit 1
            fi
            SPECIFIC_SKILL="$1"
            ;;
    esac
    shift
done

# --- Resolve target directories -------------------------------------------
TARGET_DIRS=()

if [ -z "$TARGETS_ARG" ] || [ "$TARGETS_ARG" = "all" ]; then
    TARGET_DIRS=("${ASSISTANT_DIRS[claude]}" "${ASSISTANT_DIRS[codex]}" "${ASSISTANT_DIRS[gemini]}")
else
    IFS=',' read -ra REQUESTED <<< "$TARGETS_ARG"
    for name in "${REQUESTED[@]}"; do
        name="$(echo "$name" | tr -d '[:space:]')"
        if [ -z "${ASSISTANT_DIRS[$name]+x}" ]; then
            echo "Error: Unknown target '$name'. Valid values: claude, codex, gemini, all" >&2
            exit 1
        fi
        TARGET_DIRS+=("${ASSISTANT_DIRS[$name]}")
    done
fi

# --- Discover skills in this repository -----------------------------------
SKILLS=()
for dir in "$SCRIPT_DIR"/*/; do
    [ -f "$dir/SKILL.md" ] || continue
    skill_name="$(basename "$dir")"
    # Skip hidden directories
    [[ "$skill_name" == .* ]] && continue
    SKILLS+=("$skill_name")
done

if [ ${#SKILLS[@]} -eq 0 ]; then
    echo "No skills found in $SCRIPT_DIR"
    exit 0
fi

# If a specific skill was requested, validate it belongs to this repo
if [ -n "$SPECIFIC_SKILL" ]; then
    found=false
    for skill in "${SKILLS[@]}"; do
        if [ "$skill" = "$SPECIFIC_SKILL" ]; then
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        echo "Error: Skill '$SPECIFIC_SKILL' is not provided by this repository." >&2
        echo "Available skills: ${SKILLS[*]}" >&2
        exit 1
    fi
    SKILLS=("$SPECIFIC_SKILL")
fi

# --- Uninstall skills -----------------------------------------------------
removed=0
not_installed=0

for target_dir in "${TARGET_DIRS[@]}"; do
    if [ ! -d "$target_dir" ]; then
        echo "Skipping $target_dir (does not exist)"
        echo ""
        continue
    fi

    echo "Removing from $target_dir ..."

    for skill in "${SKILLS[@]}"; do
        dest="$target_dir/$skill"

        if [ -d "$dest" ]; then
            rm -rf "$dest"
            echo "  [REMOVED]       $skill"
            removed=$((removed + 1))
        else
            echo "  [NOT INSTALLED] $skill"
            not_installed=$((not_installed + 1))
        fi
    done

    echo ""
done

# --- Summary --------------------------------------------------------------
echo "Done: $removed removed, $not_installed not installed"
