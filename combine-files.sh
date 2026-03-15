#!/usr/bin/env bash

# Combine all text files from a given folder into one combined.txt file

# If sourced: only define the function, do not run code or enable strict mode
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    combine_files() {
        "$BASH_SOURCE" "$@"
    }
    return 0
fi

# --- Direct execution only below (strict mode not active when sourced) ---

# --- Configuration & Defaults ---
TARGET_PATHS=()
TARGET_TYPES=()  # "file" or "dir" for each path
GIT_ONLY=false
CUSTOM_IGNORE_PATTERNS=()
FOLDER_IGNORE_PATTERNS=()
FILE_IGNORE_PATTERNS=()
DEFAULT_IGNORE_DIRS=("node_modules" ".next" ".git" ".github" ".venv" "__ARCHIVE__" ".cursor" ".vscode" "__pycache__")
ABS_TARGET_PATHS=()
TARGET_IS_DIR=()  # true/false for each path

show_help() {
    echo "Usage: $0 [--git-changes] [-i <ignore_pattern>]... [-d|-f] <path1> [[-d|-f] <path2>] ..."
    echo
    echo "Arguments:"
    echo "  <path>           One or more file or directory paths (required, positional)"
    echo "                   Precede each path with -d (directory) or -f (file) to specify type"
    echo "                   If omitted, type is auto-detected (warns if not found)"
    echo
    echo "Options:"
    echo "  --git-changes    Only include staged and unstaged modified files"
    echo "  -d <path>        Explicitly mark next path as a directory"
    echo "  -f <path>        Explicitly mark next path as a file"
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
    echo "  $0 -d src/lib/cms -f src/lib/utils.js"
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
    local next_type=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --git-changes)
                GIT_ONLY=true
                shift
                ;;
            -d)
                next_type="dir"
                shift
                ;;
            -f)
                next_type="file"
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
                TARGET_TYPES+=("${next_type:-}")
                next_type=""
                shift
                ;;
        esac
    done

    if [ ${#TARGET_PATHS[@]} -eq 0 ]; then
        error_exit "You must specify at least one path as an argument"
    fi
}

normalize_and_validate_paths() {
    # Normalize and validate each path (non-terminating validation)
    local idx=0
    for path in "${TARGET_PATHS[@]}"; do
        # Normalize path: convert backslashes to forward slashes
        # This handles unquoted Windows-style paths like src\lib\auth
        local normalized_path="${path//\\//}"
        
        # Check if path exists first (as relative path from current directory)
        if [ ! -e "$normalized_path" ] && [ ! -f "$normalized_path" ] && [ ! -d "$normalized_path" ]; then
            echo "⚠️  Warning: Path not found: '$path' (normalized: '$normalized_path')" >&2
            idx=$((idx + 1))
            continue
        fi
        
        # Try to resolve to absolute path
        # realpath requires path to exist, which we've already checked
        local abs_path=""
        abs_path=$(realpath "$normalized_path" 2>/dev/null || echo "")
        
        # Fallback: if realpath fails, construct absolute path manually
        if [ -z "$abs_path" ]; then
            local cwd
            cwd="$(pwd)"
            if [[ "$normalized_path" == /* ]]; then
                # Already absolute
                abs_path="$normalized_path"
            else
                # Relative path - combine with current directory
                # Remove any leading ./ for cleaner paths
                normalized_path="${normalized_path#./}"
                abs_path="$cwd/$normalized_path"
                # Normalize: resolve to canonical path by removing .. and .
                # Use cd to resolve symlinks and .. components
                local abs_dir
                abs_dir=$(cd "$(dirname "$abs_path")" 2>/dev/null && pwd) || abs_dir="$(dirname "$abs_path")"
                abs_path="$abs_dir/$(basename "$abs_path")"
            fi
        fi
        
        # Get expected type for this path
        local expected_type="${TARGET_TYPES[$idx]}"
        
        # Validate absolute path exists (should be redundant but safe)
        if [ -z "$abs_path" ] || ([ ! -e "$abs_path" ] && [ ! -f "$abs_path" ] && [ ! -d "$abs_path" ]); then
            echo "⚠️  Warning: Path not found: '$path' (resolved to: '$abs_path')" >&2
            idx=$((idx + 1))
            continue
        fi
        
        local is_dir=false
        local is_file=false
        
        if [ -d "$abs_path" ]; then
            is_dir=true
        elif [ -f "$abs_path" ]; then
            is_file=true
        else
            echo "⚠️  Warning: Path exists but is neither file nor directory: '$path'" >&2
            idx=$((idx + 1))
            continue
        fi
        
        # Check type constraint if specified
        if [ -n "$expected_type" ]; then
            if [ "$expected_type" = "dir" ] && [ "$is_file" = true ]; then
                echo "⚠️  Warning: Path marked as directory (-d) but is a file: '$path'" >&2
                idx=$((idx + 1))
                continue
            elif [ "$expected_type" = "file" ] && [ "$is_dir" = true ]; then
                echo "⚠️  Warning: Path marked as file (-f) but is a directory: '$path'" >&2
                idx=$((idx + 1))
                continue
            fi
        fi
        
        # Path is valid - add it
        ABS_TARGET_PATHS+=("$abs_path")
        if [ "$is_dir" = true ]; then
            TARGET_IS_DIR+=("true")
        else
            TARGET_IS_DIR+=("false")
        fi
        
        idx=$((idx + 1))
    done
    
    # Only fail if no valid inputs remain
    if [ ${#ABS_TARGET_PATHS[@]} -eq 0 ]; then
        error_exit "No valid files or directories were provided"
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
    local target_path="$2"
    local target_is_dir="$3"
    local basename
    basename="$(basename "$file_path")"

    # Always ignore combined.txt files (from previous runs in child folders)
    if [ "$basename" = "combined.txt" ]; then
        return 0
    fi

    # Compute relative path based on target type
    local rel_path
    if [ "$target_is_dir" = "true" ]; then
        # For directories, compute relative path from target
        rel_path="${file_path#$target_path/}"
        # If substitution didn't work, file is not under target
        if [ "$rel_path" = "$file_path" ]; then
            # File is not under this target directory, skip it
            return 0
        fi
    else
        # For files, compute relative path from directory containing the target file
        local target_dir
        target_dir="$(dirname "$target_path")"
        rel_path="${file_path#$target_dir/}"
        # If substitution didn't work and paths don't match, use basename
        if [ "$rel_path" = "$file_path" ] && [ "$file_path" != "$target_path" ]; then
            # File is not in the same directory, use basename for pattern matching
            rel_path="$basename"
        elif [ "$file_path" = "$target_path" ]; then
            # Same file, use basename
            rel_path="$basename"
        fi
    fi

    # Check folder patterns against the path parts
    if [ -n "$rel_path" ]; then
        IFS='/' read -ra PATH_PARTS <<< "$rel_path" || true
        for part in "${PATH_PARTS[@]}"; do
            [ -z "$part" ] && continue
            for pattern in "${FOLDER_IGNORE_PATTERNS[@]}"; do
                if [[ "$part" =~ $pattern ]]; then
                    return 0
                fi
            done
        done
    fi

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
    local target_is_dir="$2"
    
    # If target is a file, return it directly
    if [ "$target_is_dir" = "false" ]; then
        echo "$target_path"
        return
    fi
    
    # Target is a directory - proceed with directory traversal
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
    # Determine output location based on rule:
    # - If exactly 1 valid argument AND it is a directory → save to that directory
    # - Else → save to current working directory
    local output_dir
    if [ ${#ABS_TARGET_PATHS[@]} -eq 1 ] && [ "${TARGET_IS_DIR[0]}" = "true" ]; then
        output_dir="${ABS_TARGET_PATHS[0]}"
    else
        output_dir="$(pwd)"
    fi
    
    local output_file="$output_dir/combined.txt"

    # Remove existing combined.txt if it exists
    if [ -f "$output_file" ]; then
        echo "Removing existing combined.txt file..."
        rm "$output_file"
    fi

    # Collect all files from all paths
    local all_files=()
    local idx=0
    
    for abs_target_path in "${ABS_TARGET_PATHS[@]}"; do
        local target_is_dir="${TARGET_IS_DIR[$idx]}"
        
        if [ "$GIT_ONLY" = true ]; then
            if [ "$target_is_dir" = "true" ]; then
                echo "Collecting git-modified files under: $abs_target_path"
            else
                echo "Collecting git-modified file: $abs_target_path"
            fi
        else
            if [ "$target_is_dir" = "true" ]; then
                echo "Collecting files under: $abs_target_path"
            else
                echo "Collecting file: $abs_target_path"
            fi
        fi

        # Collect files from get_files output
        local files_from_target
        files_from_target=$(get_files "$abs_target_path" "$target_is_dir" 2>&1) || true
        
        # Process each file
        if [ -n "$files_from_target" ]; then
            while IFS= read -r file || [ -n "$file" ]; do
                [ -z "$file" ] && continue
                if ! should_skip "$file" "$abs_target_path" "$target_is_dir"; then
                    all_files+=("$file")
                fi
            done <<< "$files_from_target"
        fi
        
        idx=$((idx + 1))
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

main() {
    set -euo pipefail
    parse_args "$@"
    normalize_and_validate_paths
    setup_ignore_patterns
    combine_files
}

# Only run main when executed directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
