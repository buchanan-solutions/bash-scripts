#!/bin/bash

# --- Configuration & Logging ---
OUTPUT_FILENAME="git_audit.txt"
CWD=$(pwd)
REF_LIMIT=""

# Files/patterns to exclude from audit (simple patterns, will be converted to pathspecs)
# Use glob patterns like "*.svg" or specific files like "package-lock.json"
# For files in subdirectories, use "**/package-lock.json" to catch them anywhere
EXCLUDE_PATTERNS=("**/package-lock.json" "*.svg" "**/pnpm-lock.yaml" "**/pnpm-lock.yml")

# Simple logging helpers
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }
log_err()  { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

show_help() {
    echo "Usage: $0 [--ref REF] [directory_paths...]"
    echo
    echo "Description:"
    echo "  Performs a chronological audit of git commits including full diffs."
    echo "  Saves the result to '$OUTPUT_FILENAME' inside each targeted repo."
    echo
    echo "Options:"
    echo "  --ref REF          Limit commits to go back from HEAD (e.g., HEAD~10, abc123, or a branch name)"
    echo
    echo "Arguments:"
    echo "  directory_paths    One or more relative paths to git repositories."
    echo "  .                  Run audit on the current directory."
    exit 0
}

# --- Check for help ---
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
fi

# --- Argument Processing ---
# Parse --ref flag and collect directory targets
TARGETS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --ref)
            if [[ -z "$2" ]]; then
                log_err "--ref requires a value"
                exit 1
            fi
            REF_LIMIT="$2"
            shift 2
            ;;
        *)
            TARGETS+=("$1")
            shift
            ;;
    esac
done

# If no args, default to current directory
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=(".")
fi

# --- Core Logic ---
run_audit() {
    local target_path="$1"
    
    # Resolve absolute path to handle the 'cd' cleanly
    local abs_path
    abs_path=$(realpath "$target_path" 2>/dev/null)

    if [ ! -d "$abs_path" ]; then
        log_err "Path '$target_path' does not exist. Skipping."
        return
    fi

    # Move into the directory
    cd "$abs_path" || return

    # Check if it is a Git Repo
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        log_warn "NOT A GIT REPO: '$target_path' - Skipping audit."
        cd "$CWD" || exit
        return
    fi

    log_info "Analyzing Git Repo: $target_path"
    
    # Validate ref if provided
    local ref_args=()
    if [[ -n "$REF_LIMIT" ]]; then
        if ! git rev-parse --verify "$REF_LIMIT" > /dev/null 2>&1; then
            log_err "Invalid ref '$REF_LIMIT' in repo '$target_path'. Skipping audit."
            cd "$CWD" || exit
            return
        fi
        ref_args=("$REF_LIMIT"..HEAD)
        log_info "Limiting audit to commits from ref: $REF_LIMIT"
    fi
    
    # Build pathspec array: start with '.' to include everything, then add exclusions
    # Use :(exclude,glob) to enable glob pattern matching (needed for **/ patterns)
    local pathspecs=(".")
    for item in "${EXCLUDE_PATTERNS[@]}"; do
        pathspecs+=(":(exclude,glob)$item")
    done
    
    log_info "Running audit (Excluding: ${EXCLUDE_PATTERNS[*]})"
    
    # The Audit Command
    # --reverse: Oldest to newest (chronological)
    # --patch: Full diffs
    # --stat: File change summary
    # The '--' separator is REQUIRED to distinguish git flags from pathspecs
    # pathspecs array comes after '--' to ensure proper filtering
    git log --reverse --patch --stat \
        --pretty=format:"------------------------------------------------------------------%nCOMMIT: %H%nAUTHOR: %an <%ae>%nDATE:   %ad%nSUBJECT: %s%n------------------------------------------------------------------%n%b%n" \
        "${ref_args[@]}" \
        -- "${pathspecs[@]}" \
        > "$OUTPUT_FILENAME"

    # Count lines in output file
    local line_count
    line_count=$(wc -l < "$OUTPUT_FILENAME" 2>/dev/null || echo "0")
    
    log_info "Audit successful. Saved to: $target_path/$OUTPUT_FILENAME"
    log_info "Output file contains $line_count lines"

    # Return to base
    cd "$CWD" || exit
}

# --- Execution ---
for target in "${TARGETS[@]}"; do
    # Remove trailing colons if user uses "dir:flags" pattern by accident
    clean_target="${target%%:*}"
    run_audit "$clean_target"
done

log_info "All tasks complete."