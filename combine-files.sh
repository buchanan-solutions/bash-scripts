#!/bin/bash
set -euo pipefail

# If sourced (for bash function) vs executed directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # The file is being sourced — define a function
    combine_files() {
        "$BASH_SOURCE" "$@"
    }
    return 0
fi

# Combine all text files from a given folder into one combined.txt file

# --- Configuration & Defaults ---
TARGET_PATHS=()
GIT_ONLY=false
CUSTOM_IGNORE_PATTERNS=()
FOLDER_IGNORE_PATTERNS=()
FILE_IGNORE_PATTERNS=()
DEFAULT_IGNORE_DIRS=("node_modules" ".next" ".git" ".github" ".venv" "__ARCHIVE__" ".cursor" ".vscode" "__pycache__")
ABS_TARGET_PATHS=()

show_help() {
    echo "Usage: $0 [--git-changes] [-i <ignore_pattern>]... <path1> [path2] [path3] ..."
    echo
    echo "Arguments:"
    echo "  <path>           One or more directory paths (required, positional)"
    echo
    echo "Options:"
    echo "  --git-changes    Only include staged and unstaged modified files"
    echo "  -i <pattern>     Add ignore pattern (can be used multiple times)"
    echo "                  Use 'folder:pattern' for folder-only patterns (regex supported)"
    echo "                  Use 'file:pattern' for file-only patterns (regex supported)"
    echo "                  Plain pattern defaults to folder pattern (backward compatible)"
    echo "  -h, --help       Show this help message"
    echo
    echo "Examples:"
    echo "  $0 src/lib/cms"
    echo "  $0 ./src/lib/cms"
    echo "  $0 src\\lib\\cms"
    echo "  $0 . --git-changes"
    echo "  $0 src/lib/cms -i types -i tests"
    echo "  $0 ./src -i node_modules -i dist -i build"
    echo "  $0 ./src -i 'folder:^test' -i 'file:\\.log$'"
    echo "  $0 ./src -i 'folder:.*test.*' -i 'file:.*\\.(log|tmp)$'"
    echo "  $0 some/relative/path/1 some/relative/path/2"
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

    # Parse flags first, collect positional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            -*)
                error_exit "Invalid option: $1"
                ;;
            *)
                # Positional argument (path)
                TARGET_PATHS+=("$1")
                shift
                ;;
        esac
    done

    if [ ${#TARGET_PATHS[@]} -eq 0 ]; then
        error_exit "You must specify at least one path as an argument"
    fi
}

normalize_and_validate_paths() {
    # Normalize and validate each path
    for path in "${TARGET_PATHS[@]}"; do
        # Normalize path: convert backslashes to forward slashes
        # This handles unquoted Windows-style paths like src\lib\auth
        local normalized_path="${path//\\//}"
        
        # Try to resolve to absolute path
        local abs_path
        abs_path=$(realpath "$normalized_path" 2>/dev/null || true)
        
        # Validate path exists
        if [ -z "$abs_path" ] || [ ! -d "$abs_path" ]; then
            error_exit "Path does not exist or is not a directory: '$path'"
        fi
        
        ABS_TARGET_PATHS+=("$abs_path")
    done
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
    local target_path="$2"
    local rel_path="${file_path#$target_path/}"
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
    local target_path="$1"
    
    if [ "$GIT_ONLY" = true ]; then
        if ! is_git_repo; then
            error_exit "--git-changes used but $(pwd) is not a git repository"
        fi

        # Use git status --porcelain=v1
        # We pass "$target_path" to git to filter files at the engine level
        # This is more reliable than manual string matching in Bash
        git status --porcelain=v1 -- "$target_path" 2>/dev/null | while IFS= read -r line; do
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
        find "$target_path" -type f | sort
    fi
}

combine_files() {
    # Use the first path as the output location
    local output_path="${ABS_TARGET_PATHS[0]}"
    local output_file="$output_path/combined.txt"

    # Remove existing combined.txt if it exists
    if [ -f "$output_file" ]; then
        echo "Removing existing combined.txt file..."
        rm "$output_file"
    fi

    # Collect all files from all paths
    local all_files=()
    
    for abs_target_path in "${ABS_TARGET_PATHS[@]}"; do
        if [ "$GIT_ONLY" = true ]; then
            echo "Collecting git-modified files under: $abs_target_path"
        else
            echo "Collecting files under: $abs_target_path"
        fi

        while IFS= read -r file; do
            if ! should_skip "$file" "$abs_target_path"; then
                all_files+=("$file")
            fi
        done < <(get_files "$abs_target_path")
    done

    if [ ${#all_files[@]} -eq 0 ]; then
        if [ "$GIT_ONLY" = true ]; then
            echo "No git-modified files found in any of the specified paths"
        else
            echo "No files found in any of the specified paths"
        fi
        return
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
normalize_and_validate_paths
setup_ignore_patterns
combine_files
