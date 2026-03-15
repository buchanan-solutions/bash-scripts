#!/bin/bash

# If sourced (for bash function) vs executed directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    text_search() {
        "$BASH_SOURCE" "$@"
    }
    return 0
fi

# -----------------------------
# Help
# -----------------------------
show_help() {
    echo "Usage: $0 [options] <regex>"
    echo
    echo "Description:"
    echo "  Recursively searches for unique regex matches and groups files by match."
    echo
    echo "Options:"
    echo "  -f <folder>                  Root folder (default: .)"
    echo "  -i <dir1,dir2,...>           Append exclude directories (comma separated)"
    echo "  -ignore-default-exclude      Disable default excludes"
    echo "  -h, --help                   Show help"
    echo
    echo "Default Excluded Directories:"
    echo "  node_modules, .next, dist, build, .git"
    echo
    echo "Example:"
    echo "  text_search -f src -i \"coverage,.cache\" 'process\\.env\\.[A-Za-z0-9_]+'"
    exit 0
}

# -----------------------------
# Defaults
# -----------------------------
SEARCH_FOLDER="."
DEFAULT_EXCLUDES=("node_modules" ".next" "dist" "build" ".git")
USE_DEFAULT_EXCLUDES=true
APPEND_EXCLUDES=()

# -----------------------------
# Parse Args
# -----------------------------
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f)
            SEARCH_FOLDER="$2"
            shift 2
            ;;
        -i)
            IFS=',' read -r -a EXTRA <<< "$2"
            for dir in "${EXTRA[@]}"; do
                APPEND_EXCLUDES+=("$(echo "$dir" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')")
            done
            shift 2
            ;;
        -ignore-default-exclude)
            USE_DEFAULT_EXCLUDES=false
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Require regex
if [ ${#POSITIONAL_ARGS[@]} -eq 0 ]; then
    echo "Error: regex argument required." >&2
    exit 1
fi

REGEX="${POSITIONAL_ARGS[-1]}"

# -----------------------------
# Build Exclude Args
# -----------------------------
EXCLUDE_DIRS=()

if [ "$USE_DEFAULT_EXCLUDES" = true ]; then
    EXCLUDE_DIRS+=("${DEFAULT_EXCLUDES[@]}")
fi

if [ ${#APPEND_EXCLUDES[@]} -gt 0 ]; then
    EXCLUDE_DIRS+=("${APPEND_EXCLUDES[@]}")
fi

EXCLUDE_ARGS=()
for dir in "${EXCLUDE_DIRS[@]}"; do
    EXCLUDE_ARGS+=(--exclude-dir="$dir")
done

# -----------------------------
# Core Command (UNCHANGED LOGIC)
# -----------------------------
grep -RhoE "$REGEX" "$SEARCH_FOLDER" \
  "${EXCLUDE_ARGS[@]}" \
| sort -u \
| while read var; do
    grep -Rl "$var" "$SEARCH_FOLDER" \
      "${EXCLUDE_ARGS[@]}" \
    | sort \
    | sed "s|^|$var |"
  done