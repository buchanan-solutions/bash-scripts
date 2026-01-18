#!/bin/bash
set -euo pipefail

# Combine all text files from a given folder into one combined.txt file

# --- Configuration & Defaults ---
TARGET_PATH=""
GIT_ONLY=false
CUSTOM_IGNORE_PATTERNS=()
FOLDER_IGNORE_PATTERNS=()
FILE_IGNORE_PATTERNS=()
DEFAULT_IGNORE_DIRS=("node_modules" ".next" ".git" ".github" ".venv" "__ARCHIVE__" ".cursor" ".vscode" "__pycache__")
ABS_TARGET_PATH=""

show_help() {
    echo "Usage: $0 -p <relative_or_absolute_path> [--git-changes] [-i <ignore_pattern>]..."
    echo
    echo "Options:"
    echo "  -p <path>        Target directory path (required)"
    echo "  --git-changes    Only include staged and unstaged modified files"
    echo "  -i <pattern>     Add ignore pattern (can be used multiple times)"
    echo "                  Use 'folder:pattern' for folder-only patterns (regex supported)"
    echo "                  Use 'file:pattern' for file-only patterns (regex supported)"
    echo "                  Plain pattern defaults to folder pattern (backward compatible)"
    echo "  -h, --help       Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -p src/lib/cms"
    echo "  $0 -p ./src/lib/cms"
    echo "  $0 -p src\\lib\\cms"
    echo "  $0 -p . --git-changes"
    echo "  $0 -p src/lib/cms -i types -i tests"
    echo "  $0 -p ./src -i node_modules -i dist -i build"
    echo "  $0 -p ./src -i 'folder:^test' -i 'file:\\.log$'"
    echo "  $0 -p ./src -i 'folder:.*test.*' -i 'file:.*\\.(log|tmp)$'"
    echo
    echo "Default ignored directories:"
    echo "  node_modules, .next, .git, .github, .venv, __ARCHIVE__, .cursor, .vscode, __pycache__"
    exit 0
}

# --- Utility Functions ---

error_exit() {
    echo "Error: $1" >&2
    exit 1
}

is_git_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# --- Logic Functions ---

parse_args() {
    # Check for help flags first
    for arg in "$@"; do
        if [[ "$arg" == "--help" ]] || [[ "$arg" == "-h" ]]; then
            show_help
        fi
    done

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p)
                TARGET_PATH="$2"
                shift 2
                ;;
            --git-changes)
                GIT_ONLY=true
                shift
                ;;
            -i)
                CUSTOM_IGNORE_PATTERNS+=("$2")
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                error_exit "Invalid option: $1"
                ;;
        esac
    done

    if [ -z "$TARGET_PATH" ]; then
        error_exit "You must specify a path with -p"
    fi

    # Normalize path (handle Windows-style slashes)
    TARGET_PATH="${TARGET_PATH//\\//}"
    ABS_TARGET_PATH="$(realpath "$TARGET_PATH" 2>/dev/null || true)"

    if [ ! -d "$ABS_TARGET_PATH" ]; then
        error_exit "'$TARGET_PATH' is not a valid directory"
    fi
}

setup_ignore_patterns() {
    # Default ignored directories (as folder patterns)
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
}

should_skip() {
    local file_path="$1"
    local rel_path="${file_path#$ABS_TARGET_PATH/}"
    local basename="$(basename "$file_path")"

    # Always ignore combined.txt files (from previous runs in child folders)
    if [ "$basename" = "combined.txt" ]; then
        return 0
    fi

    # Check folder patterns against the path
    IFS='/' read -ra PATH_PARTS <<< "$rel_path"
    for part in "${PATH_PARTS[@]}"; do
        for pattern in "${FOLDER_IGNORE_PATTERNS[@]}"; do
            if [[ "$part" =~ $pattern ]]; then
                return 0
            fi
        done
    done

    # Check file patterns against the filename
    for pattern in "${FILE_IGNORE_PATTERNS[@]}"; do
        if [[ "$basename" =~ $pattern ]]; then
            return 0
        fi
    done

    return 1 # Do not skip
}

get_files() {
    if [ "$GIT_ONLY" = true ]; then
        if ! is_git_repo; then
            error_exit "--git-changes used but $(pwd) is not a git repository"
        fi

        # Use git status --porcelain=v1
        # We pass "$ABS_TARGET_PATH" to git to filter files at the engine level
        # This is more reliable than manual string matching in Bash
        git status --porcelain=v1 -- "$ABS_TARGET_PATH" 2>/dev/null | while IFS= read -r line; do
            [ -z "$line" ] && continue
            
            # Extract filename (handle porcelain format: XY path or XY "path")
            # Index 3 to end of line is the path
            local raw_path="${line:3}"
            
            # Strip quotes if present (Git adds them if there are special chars/spaces)
            raw_path="${raw_path%\"}"
            raw_path="${raw_path#\"}"

            # Convert whatever Git gave us into a clean absolute path
            # This handles the relative-to-root vs absolute path issues
            local abs_file
            abs_file=$(realpath "$raw_path" 2>/dev/null || true)

            # Final check: is it a real file and does it actually exist?
            if [ -f "$abs_file" ]; then
                echo "$abs_file"
            fi
        done | sort -u
    else
        find "$ABS_TARGET_PATH" -type f | sort
    fi
}

combine_files() {
    local output_file="$ABS_TARGET_PATH/combined.txt"

    # Remove existing combined.txt if it exists
    if [ -f "$output_file" ]; then
        echo "Removing existing combined.txt file..."
        rm "$output_file"
    fi

    # Collect all files
    if [ "$GIT_ONLY" = true ]; then
        echo "Collecting git-modified files under: $ABS_TARGET_PATH"
    else
        echo "Collecting files under: $ABS_TARGET_PATH"
    fi

    local all_files=()
    while IFS= read -r file; do
        if ! should_skip "$file"; then
            all_files+=("$file")
        fi
    done < <(get_files)

    if [ ${#all_files[@]} -eq 0 ]; then
        if [ "$GIT_ONLY" = true ]; then
            echo "No git-modified files found under $ABS_TARGET_PATH"
        else
            echo "No files found under $ABS_TARGET_PATH"
        fi
        exit 0
    fi

    # Combine into one file
    echo "Combining ${#all_files[@]} files into $output_file..."
    : > "$output_file"

    for file in "${all_files[@]}"; do
        {
            echo "$file:"
            cat "$file"
            echo -e "\n"
        } >> "$output_file"
    done

    # Count total lines in the combined file
    local total_lines
    total_lines=$(wc -l < "$output_file" | tr -d ' ')
    echo "✅ Combined ${#all_files[@]} files into $total_lines lines"
    echo "File saved to: $output_file"
}

# --- Execution ---

parse_args "$@"
setup_ignore_patterns
combine_files
