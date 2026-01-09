#!/bin/bash
set -euo pipefail

# Combine all text files from a given folder into one combined.txt file

show_help() {
    echo "Usage: $0 -p <relative_or_absolute_path> [-i <ignore_pattern>]..."
    echo
    echo "Options:"
    echo "  -p <path>     Target directory path (required)"
    echo "  -i <pattern>  Add ignore pattern (can be used multiple times)"
    echo "                Use 'folder:pattern' for folder-only patterns (regex supported)"
    echo "                Use 'file:pattern' for file-only patterns (regex supported)"
    echo "                Plain pattern defaults to folder pattern (backward compatible)"
    echo "  -h, --help    Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -p src/lib/cms"
    echo "  $0 -p ./src/lib/cms"
    echo "  $0 -p src\\lib\\cms"
    echo "  $0 -p src/lib/cms -i types -i tests"
    echo "  $0 -p ./src -i node_modules -i dist -i build"
    echo "  $0 -p ./src -i 'folder:^test' -i 'file:\\.log$'"
    echo "  $0 -p ./src -i 'folder:.*test.*' -i 'file:.*\\.(log|tmp)$'"
    echo
    echo "Default ignored directories:"
    echo "  node_modules, .next, .git, .github, .venv, __ARCHIVE__, .cursor, .vscode, __pycache__"
    exit 0
}

# --- Check for help flags before parsing other arguments ---
for arg in "$@"; do
    if [[ "$arg" == "--help" ]] || [[ "$arg" == "-h" ]]; then
        show_help
    fi
done

# --- Parse arguments ---
TARGET_PATH=""
CUSTOM_IGNORE_PATTERNS=()
while getopts ":p:i:h" opt; do
  case $opt in
    p)
      TARGET_PATH="$OPTARG"
      ;;
    i)
      CUSTOM_IGNORE_PATTERNS+=("$OPTARG")
      ;;
    h)
      show_help
      ;;
    *)
      echo "Error: Invalid option -$OPTARG" >&2
      show_help
      ;;
  esac
done

if [ -z "$TARGET_PATH" ]; then
    echo "Error: You must specify a path with -p" >&2
    show_help
fi

# --- Normalize path (handle Windows-style slashes) ---
TARGET_PATH="${TARGET_PATH//\\//}"
ABS_TARGET_PATH="$(realpath "$TARGET_PATH" 2>/dev/null || true)"

if [ ! -d "$ABS_TARGET_PATH" ]; then
    echo "Error: '$TARGET_PATH' is not a valid directory" >&2
    exit 1
fi

OUTPUT_FILE="$ABS_TARGET_PATH/combined.txt"

# --- Remove existing combined.txt if it exists ---
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing combined.txt file..."
    rm "$OUTPUT_FILE"
fi

# --- Parse ignore patterns into folder and file patterns ---
FOLDER_IGNORE_PATTERNS=()
FILE_IGNORE_PATTERNS=()

# Default ignored directories (as folder patterns)
DEFAULT_IGNORE_DIRS=("node_modules" ".next" ".git" ".github" ".venv" "__ARCHIVE__" ".cursor" ".vscode" "__pycache__")
for dir in "${DEFAULT_IGNORE_DIRS[@]}"; do
    FOLDER_IGNORE_PATTERNS+=("^${dir}$")
done

# Parse custom ignore patterns
for pattern in "${CUSTOM_IGNORE_PATTERNS[@]}"; do
    if [[ "$pattern" =~ ^folder:(.+)$ ]]; then
        # Folder pattern: extract pattern after "folder:"
        FOLDER_IGNORE_PATTERNS+=("${BASH_REMATCH[1]}")
    elif [[ "$pattern" =~ ^file:(.+)$ ]]; then
        # File pattern: extract pattern after "file:"
        FILE_IGNORE_PATTERNS+=("${BASH_REMATCH[1]}")
    else
        # Default: treat as folder pattern (backward compatible)
        # Escape special regex chars for exact match, but allow regex if user provides them
        FOLDER_IGNORE_PATTERNS+=("$pattern")
    fi
done

# --- Collect all files (alphabetically by folder then by filename) ---
echo "Collecting files under: $ABS_TARGET_PATH"
mapfile -t ALL_FILES < <(
    find "$ABS_TARGET_PATH" -type f \
    | sort \
    | while read -r FILE; do
        SKIP=false
        # Get relative path from target directory to check ignores relative to target
        RELATIVE_FILE_PATH="${FILE#$ABS_TARGET_PATH/}"
        BASENAME="$(basename "$FILE")"
        
        # Always ignore combined.txt files (from previous runs in child folders)
        if [ "$BASENAME" = "combined.txt" ]; then
            SKIP=true
        fi
        
        # Check folder patterns against the path
        for pattern in "${FOLDER_IGNORE_PATTERNS[@]}"; do
            # Check if any directory component in the path matches the pattern
            IFS='/' read -ra PATH_PARTS <<< "$RELATIVE_FILE_PATH"
            for part in "${PATH_PARTS[@]}"; do
                if [[ "$part" =~ $pattern ]]; then
                    SKIP=true
                    break 2
                fi
            done
        done
        
        # Check file patterns against the filename
        if [ "$SKIP" = false ]; then
            for pattern in "${FILE_IGNORE_PATTERNS[@]}"; do
                if [[ "$BASENAME" =~ $pattern ]]; then
                    SKIP=true
                    break
                fi
            done
        fi
        
        if [ "$SKIP" = false ]; then
            echo "$FILE"
        fi
    done
)

if [ ${#ALL_FILES[@]} -eq 0 ]; then
    echo "No files found under $ABS_TARGET_PATH"
    exit 0
fi

# --- Combine into one file ---
echo "Combining ${#ALL_FILES[@]} files into $OUTPUT_FILE..."
: > "$OUTPUT_FILE"

for FILE in "${ALL_FILES[@]}"; do
    {
        echo "$FILE:"
        cat "$FILE"
        echo -e "\n"
    } >> "$OUTPUT_FILE"
done

# Count total lines in the combined file
TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
echo "✅ Combined ${#ALL_FILES[@]} files into $TOTAL_LINES lines"
echo "File saved to: $OUTPUT_FILE"
