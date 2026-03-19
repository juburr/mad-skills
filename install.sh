#!/usr/bin/env bash
# Install skills from this repository into the skills directories for
# Claude Code, Codex, and Gemini CLI.
#
# Usage:
#   bash install.sh                              # Install new skills only (skip existing)
#   bash install.sh --overwrite                  # Replace existing skills with same name
#   bash install.sh --overwrite NAME             # Replace only the named skill
#   bash install.sh --targets claude,codex       # Install to specific assistants only
#
# Skills are directories containing a SKILL.md file at the top level of this
# repository. Hidden directories and files without SKILL.md are ignored.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERWRITE=false
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
        --overwrite)
            OVERWRITE=true
            if [ $# -gt 1 ] && [[ ! "$2" == --* ]]; then
                SPECIFIC_SKILL="$2"
                shift
            fi
            ;;
        --targets)
            if [ $# -lt 2 ]; then
                echo "Error: --targets requires a value (e.g., --targets claude,codex)" >&2
                exit 1
            fi
            TARGETS_ARG="$2"
            shift
            ;;
        -h|--help)
            echo "Usage: bash install.sh [--overwrite [skill-name]] [--targets LIST]"
            echo ""
            echo "Options:"
            echo "  --overwrite              Replace all existing skills that have the same name"
            echo "  --overwrite <skill-name> Replace only the named skill"
            echo "  --targets <list>         Comma-separated list of coding assistants to install to"
            echo "                           Valid values: claude, codex, gemini, all (default: all)"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            echo "Run 'bash install.sh --help' for usage." >&2
            exit 1
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

# --- Discover skills ------------------------------------------------------
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

# If a specific skill was requested, validate it exists
if [ -n "$SPECIFIC_SKILL" ]; then
    found=false
    for skill in "${SKILLS[@]}"; do
        if [ "$skill" = "$SPECIFIC_SKILL" ]; then
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        echo "Error: Skill '$SPECIFIC_SKILL' not found in repository." >&2
        echo "Available skills: ${SKILLS[*]}" >&2
        exit 1
    fi
    SKILLS=("$SPECIFIC_SKILL")
fi

# --- Install skills -------------------------------------------------------
installed=0
skipped=0
replaced=0

for target_dir in "${TARGET_DIRS[@]}"; do
    mkdir -p "$target_dir"
    echo "Installing to $target_dir ..."

    for skill in "${SKILLS[@]}"; do
        src="$SCRIPT_DIR/$skill"
        dest="$target_dir/$skill"

        if [ -d "$dest" ]; then
            if [ "$OVERWRITE" = true ]; then
                rm -rf "$dest"
                cp -r "$src" "$dest"
                echo "  [REPLACED]  $skill"
                replaced=$((replaced + 1))
            else
                echo "  [SKIPPED]   $skill (already exists; use --overwrite to replace)"
                skipped=$((skipped + 1))
            fi
        else
            cp -r "$src" "$dest"
            echo "  [INSTALLED] $skill"
            installed=$((installed + 1))
        fi
    done

    echo ""
done

# --- Summary --------------------------------------------------------------
echo "Done: $installed installed, $replaced replaced, $skipped skipped"
