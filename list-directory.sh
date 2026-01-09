#!/bin/bash

# Source debug function
source "$(dirname "$0")/logging.sh"

# Function to display help information
show_help() {
    echo "Usage: $0 [options] [directory_paths...] [directory:flags...] [.]"
    echo
    echo "Description:"
    echo "  Prints a tree-like directory structure with visual connectors (├──, └──)"
    echo "  and proper indentation. Respects .gitignore rules when run in a Git repository."
    echo "  Supports per-directory flags for fine-grained control over recursion behavior."
    echo
    echo "Arguments:"
    echo "  directory_paths    One or more directory paths to display (optional)"
    echo "  directory:flags    Directory-specific flags using 'directory:flags' syntax"
    echo "                     IMPORTANT: Must be wrapped in double quotes for proper parsing"
    echo "                     Example: \"pg_data:-d 1 -s\" (depth 1, structure only)"
    echo "  .                  Show current directory (can be combined with other paths)"
    echo
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  -ff FILE           Load directory-specific flags from a file"
    echo
    echo "Per-Directory Flags:"
    echo "  -d N, --depth N           Maximum recursion depth for this directory (default: unlimited)"
    echo "  -s, --structure-only      Show directory structure only (no files)"
    echo "  -f N, --files-only-at-level N  Show files only at the specified depth level"
    echo
    echo "Flags File Format:"
    echo "  Each line should contain: directory_name:flags"
    echo "  Empty lines and lines starting with # are ignored"
    echo "  Example flags.txt:"
    echo "    pg_data:-d 1 -s"
    echo "    logs:-f 2"
    echo "    tmp:-d 0"
    echo
    echo "Behavior:"
    echo "  - If no arguments provided: Shows current directory (.)"
    echo "  - If '.' is the only argument: Shows current directory"
    echo "  - If '.' is used with other directories: Shows current directory with"
    echo "    the specified directories prioritized/listed first"
    echo "  - If only directory paths provided: Shows each directory's tree structure"
    echo "  - Per-directory flags apply only when recursing into matching directories"
    echo
    echo "Examples:"
    echo "  $0                                    # Show current directory"
    echo "  $0 .                                  # Show current directory"
    echo "  $0 src                                # Show src/ directory tree"
    echo "  $0 src lib                            # Show src/ and lib/ directory trees"
    echo "  $0 . src lib                          # Show current directory with src/ and lib/ prioritized"
    echo "  $0 src \"pg_data:-d 1 -s\" \"logs:-f 2\"  # Show src/, pg_data with depth 1 structure-only,"
    echo "                                        #   and logs with files only at depth 2"
    echo "  $0 . \"./data:-d 1 -s\"                # Show current directory with data/ limited to depth 1"
    echo "  $0 -ff flags.txt                     # Load flags from flags.txt file"
    echo "  $0 -ff flags.txt src                 # Use flags file and show src/ directory"
    echo
    echo "Ignored Directories:"
    echo "  The following directories are always ignored:"
    echo "  node_modules, .next, .github, .venv, __ARCHIVE__, .cursor, .vscode, .git"
    echo
    echo "Git Integration:"
    echo "  If run within a Git repository, files and directories matching .gitignore"
    echo "  patterns will be automatically excluded from the output."
    exit 0
}

# --- Global variables for directory-specific flags ---
declare -A DIR_FLAGS_MAP

# Debug flag - set to "true" to enable debug logging
DEBUG=false
WARN=false

# Store current working directory for relative path calculations (set early so it's available everywhere)
CWD=$(pwd)

# --- Check for help flags before processing other arguments ---
for arg in "$@"; do
    if [[ "$arg" == "--help" ]] || [[ "$arg" == "-h" ]]; then
        show_help
    fi
done

# --- Parse command-line arguments for flags file and directory-specific flags ---
FLAGS_FILE=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -ff)
            FLAGS_FILE="$2"
            shift 2
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# --- Load flags from file if provided ---
if [ -n "$FLAGS_FILE" ] && [ -f "$FLAGS_FILE" ]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        # Remove leading/trailing whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Skip if still empty after trimming
        [[ -z "$line" ]] && continue
        # Parse directory:flags
        if [[ "$line" == *:* ]]; then
            dir="${line%%:*}"
            flags="${line#*:}"
            # Remove leading whitespace from flags
            flags=$(echo "$flags" | sed 's/^[[:space:]]*//')
            # Normalize directory name: resolve to relative path from CWD if it exists
            debug "Loading from file - dir='$dir', flags='$flags', CWD='$CWD'"
            if [ -e "$dir" ]; then
                normalized_dir=$(realpath --relative-to="$CWD" "$dir" 2>/dev/null || echo "$dir")
                # Normalize: if relative path is ".", use empty string; otherwise use the relative path
                if [ "$normalized_dir" = "." ]; then
                    normalized_dir=""
                fi
                debug "Directory exists in file - normalized_dir='$normalized_dir', storing flags"
                # Store with normalized name, but also store with original name as fallback
                DIR_FLAGS_MAP["$normalized_dir"]="$flags"
                DIR_FLAGS_MAP["$dir"]="$flags"
                debug "Stored from file: DIR_FLAGS_MAP['$normalized_dir']='$flags' and DIR_FLAGS_MAP['$dir']='$flags'"
            else
                # Directory doesn't exist yet, store as-is (will be checked during recursion)
                debug "Directory doesn't exist yet in file - storing as-is: DIR_FLAGS_MAP['$dir']='$flags'"
                DIR_FLAGS_MAP["$dir"]="$flags"
            fi
        fi
    done < "$FLAGS_FILE"
elif [ -n "$FLAGS_FILE" ]; then
    echo "Warning: Flags file '$FLAGS_FILE' not found. Ignoring." >&2
fi

# Function to parse flags string and return values via global variables
# Usage: parse_flags "flags_string" "max_depth_var" "structure_only_var" "files_only_at_level_var"
parse_flags() {
    local flags_str="$1"
    local max_depth_var="$2"
    local structure_only_var="$3"
    local files_only_at_level_var="$4"
    
    debug "parse_flags called with flags_str='$flags_str'"
    
    # Initialize defaults
    eval "$max_depth_var=\"\""
    eval "$structure_only_var=\"false\""
    eval "$files_only_at_level_var=\"\""
    
    if [ -z "$flags_str" ]; then
        debug "parse_flags - empty flags_str, returning"
        return
    fi
    
    # Parse flags string
    local flags_array=()
    read -r -a flags_array <<< "$flags_str"
    debug "parse_flags - flags_array=(${flags_array[*]})"
    
    local i=0
    while [ $i -lt ${#flags_array[@]} ]; do
        case "${flags_array[$i]}" in
            -d|--depth)
                i=$((i + 1))
                if [ $i -lt ${#flags_array[@]} ]; then
                    eval "$max_depth_var=\"${flags_array[$i]}\""
                    debug "parse_flags - set $max_depth_var='${flags_array[$i]}'"
                fi
                ;;
            -s|--structure-only)
                eval "$structure_only_var=\"true\""
                debug "parse_flags - set $structure_only_var='true'"
                ;;
            -f|--files-only-at-level)
                i=$((i + 1))
                if [ $i -lt ${#flags_array[@]} ]; then
                    eval "$files_only_at_level_var=\"${flags_array[$i]}\""
                    debug "parse_flags - set $files_only_at_level_var='${flags_array[$i]}'"
                fi
                ;;
        esac
        i=$((i + 1))
    done
    debug "parse_flags - final values: $max_depth_var='$(eval echo \$$max_depth_var)', $structure_only_var='$(eval echo \$$structure_only_var)', $files_only_at_level_var='$(eval echo \$$files_only_at_level_var)'"
}

# Function to print the children of a directory with connectors and proper indentation.
print_children_of_path() {
    local parent_path="$1"
    local indent="$2"
    local git_repo_root="$3"
    local explicit_dirs_to_prioritize_str="$4"
    local max_depth="$5"
    local current_depth="$6"
    local structure_only="$7"
    local files_only_at_level="$8"
    local relative_depth_in_flagged="${9:-0}"  # Depth relative to flagged directory (default 0)

    # DEBUG: Log entry into function
    debug "print_children_of_path called with parent_path='$parent_path', current_depth=$current_depth, relative_depth_in_flagged=$relative_depth_in_flagged"
    
    # Check if this folder has specific flags
    # Use relative path from CWD for matching, not just basename
    local folder_basename
    folder_basename=$(basename "$parent_path")
    
    local rel_path
    rel_path=$(realpath --relative-to="$CWD" "$parent_path" 2>/dev/null || echo "$parent_path")
    # Normalize: if relative path is ".", use empty string; otherwise use the relative path
    if [ "$rel_path" = "." ]; then
        rel_path=""
    fi
    
    debug "folder_basename='$folder_basename', rel_path='$rel_path', CWD='$CWD'"
    
    local local_max_depth="$max_depth"
    local local_structure_only="$structure_only"
    local local_files_only_at_level="$files_only_at_level"
    local local_relative_depth=$relative_depth_in_flagged
    
    # DEBUG: Show DIR_FLAGS_MAP contents
    if [ "$DEBUG" = "true" ]; then
        debug "DIR_FLAGS_MAP keys: ${!DIR_FLAGS_MAP[@]}"
        for key in "${!DIR_FLAGS_MAP[@]}"; do
            debug "  DIR_FLAGS_MAP['$key']='${DIR_FLAGS_MAP[$key]}'"
        done
    fi
    
    # --- Apply per-directory flags FIRST, before any depth checks ---
    # Try matching by relative path first, then by basename
    local flags_to_apply=""
    if [ -n "$rel_path" ] && [[ -n "${DIR_FLAGS_MAP[$rel_path]}" ]]; then
        flags_to_apply="${DIR_FLAGS_MAP[$rel_path]}"
        debug "Matched flags by rel_path '$rel_path': '$flags_to_apply'"
    elif [[ -n "${DIR_FLAGS_MAP[$folder_basename]}" ]]; then
        flags_to_apply="${DIR_FLAGS_MAP[$folder_basename]}"
        debug "Matched flags by folder_basename '$folder_basename': '$flags_to_apply'"
    else
        debug "No flags matched for rel_path='$rel_path' or folder_basename='$folder_basename'"
    fi
    
    if [ -n "$flags_to_apply" ]; then
        parse_flags "$flags_to_apply" "local_max_depth" "local_structure_only" "local_files_only_at_level"
        debug "Applied flags - local_max_depth='$local_max_depth', local_structure_only='$local_structure_only', local_files_only_at_level='$local_files_only_at_level'"
        # When flags are applied, reset relative depth to 0 (this directory is the new root for depth calculation)
        local_relative_depth=0
        debug "Reset local_relative_depth to 0 (flags applied)"
    elif [ -n "$local_max_depth" ]; then
        # We're inside a flagged directory subtree, use the passed relative depth (it's already correct)
        local_relative_depth=$relative_depth_in_flagged
        debug "Using passed relative_depth_in_flagged=$relative_depth_in_flagged (inside flagged subtree)"
    else
        debug "No flags, no max_depth - local_relative_depth=$local_relative_depth"
    fi
    
    # Note: We don't check depth here - we want to show contents at the current level
    # Depth check will happen when deciding whether to recurse into subdirectories
    
    # Directories to always ignore, regardless of recursion depth
    local ALWAYS_IGNORE_DIRS=("node_modules" ".next" ".github" ".venv" "__ARCHIVE__" ".cursor" ".vscode")

    local sub_directories=()
    local files_in_dir=()
    local all_children_raw=()

    while IFS= read -r -d $'\0' entry; do
        all_children_raw+=("$entry")
    done < <(find "$parent_path" -maxdepth 1 -mindepth 1 -print0)

    for entry in "${all_children_raw[@]}"; do
        local entry_basename="$(basename "$entry")"

        # Always ignore certain directories
        for ignore_name in "${ALWAYS_IGNORE_DIRS[@]}"; do
            if [ "$entry_basename" = "$ignore_name" ]; then
                continue 2
            fi
        done

        # Always ignore .git directory
        if [ "$entry_basename" = ".git" ]; then
            continue
        fi

        # Check if ignored by gitignore
        if [ -n "$git_repo_root" ]; then
            local relative_entry_path
            relative_entry_path=$(realpath --relative-to="$git_repo_root" "$entry")
            if git -C "$git_repo_root" check-ignore -q "$relative_entry_path" &>/dev/null; then
                continue
            fi
        fi

        if [ -d "$entry" ]; then
            sub_directories+=("$entry")
        elif [ -f "$entry" ]; then
            files_in_dir+=("$entry")
        fi
    done

    local final_dirs=()
    local final_files=()
    local next_depth=$((current_depth + 1))

    # Handle files-only-at-level flag
    if [ -n "$local_files_only_at_level" ]; then
        if [ "$next_depth" -eq "$local_files_only_at_level" ]; then
            # Show only files at this level
            final_files=("${files_in_dir[@]}")
        else
            # Show only directories (will recurse)
            final_dirs=("${sub_directories[@]}")
        fi
    elif [ -n "$explicit_dirs_to_prioritize_str" ]; then
        IFS=' ' read -r -a explicit_dirs_array <<< "$explicit_dirs_to_prioritize_str"
        local other_sub_directories=()
        for dir_entry in "${sub_directories[@]}"; do
            local dir_basename=$(basename "$dir_entry")
            local is_explicit=false
            for explicit_name in "${explicit_dirs_array[@]}"; do
                if [ "$dir_basename" = "$explicit_name" ]; then
                    final_dirs+=("$dir_entry")
                    is_explicit=true
                    break
                fi
            done
            if [ "$is_explicit" = "false" ]; then
                other_sub_directories+=("$dir_entry")
            fi
        done
        # Add other directories after explicit ones
        final_dirs+=("${other_sub_directories[@]}")
        # Add files unless structure-only is enabled
        if [ "$local_structure_only" != "true" ]; then
            final_files=("${files_in_dir[@]}")
        fi
    else
        final_dirs=("${sub_directories[@]}")
        # Add files unless structure-only is enabled
        if [ "$local_structure_only" != "true" ]; then
            final_files=("${files_in_dir[@]}")
        fi
    fi

    IFS=$'\n' final_dirs=($(sort <<<"${final_dirs[*]}"))
    IFS=$'\n' final_files=($(sort <<<"${final_files[*]}"))
    unset IFS

    local sorted_entries=("${final_dirs[@]}" "${final_files[@]}")
    local num_entries=${#sorted_entries[@]}
    local i=0

    for entry in "${sorted_entries[@]}"; do
        i=$((i + 1))
        local is_last_entry=$([ "$i" -eq "$num_entries" ] && echo "true" || echo "false")
        local entry_basename="$(basename "$entry")"

        local connector_char=""
        local next_indent_for_children=""

        if [ "$is_last_entry" = "true" ]; then
            connector_char="└── "
            next_indent_for_children="${indent}    "
        else
            connector_char="├── "
            next_indent_for_children="${indent}│   "
        fi

        if [ -d "$entry" ]; then
            echo "${indent}${connector_char}📁 ${entry_basename}"
            # Calculate relative depth for children
            local child_relative_depth
            if [ -n "$local_max_depth" ]; then
                # We're under a depth limit, use relative depth
                child_relative_depth=$((local_relative_depth + 1))
                debug "Directory '$entry_basename' - local_max_depth='$local_max_depth', local_relative_depth=$local_relative_depth, child_relative_depth=$child_relative_depth"
            else
                # No depth limit, pass 0 (will be recalculated if flags are found)
                child_relative_depth=0
                debug "Directory '$entry_basename' - no max_depth, child_relative_depth=$child_relative_depth"
            fi
            # Check depth limit before recursing - use relative depth if we have a max_depth limit
            local should_recurse=true
            if [ -n "$local_max_depth" ]; then
                # Check relative depth against the limit (use >= to properly cut off at max_depth)
                debug "Checking depth: child_relative_depth=$child_relative_depth >= local_max_depth=$local_max_depth?"
                if [ "$child_relative_depth" -ge "$local_max_depth" ]; then
                    should_recurse=false
                    debug "NOT recursing into '$entry_basename' - depth limit reached"
                else
                    debug "WILL recurse into '$entry_basename' - depth check passed"
                fi
            else
                debug "WILL recurse into '$entry_basename' - no depth limit"
            fi
            if [ "$should_recurse" = "true" ]; then
                print_children_of_path "$entry" "$next_indent_for_children" "$git_repo_root" "" "$local_max_depth" "$next_depth" "$local_structure_only" "$local_files_only_at_level" "$child_relative_depth"
            fi
        elif [ -f "$entry" ]; then
            echo "${indent}${connector_char}${entry_basename}"
        fi
    done
}

# --- Main Script Execution ---
debug "Starting main execution - CWD='$CWD', POSITIONAL_ARGS=(${POSITIONAL_ARGS[*]})"

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$GIT_ROOT" ]; then
    warn "Not in a Git repository. .gitignore rules will not be applied."
    GIT_ROOT=""
fi

# --- Parse directory-specific flags from command-line arguments ---
declare -a explicit_target_dirs=()
root_dot_arg_present=false

for arg in "${POSITIONAL_ARGS[@]}"; do
    if [ "$arg" = "." ]; then
        root_dot_arg_present=true
    elif [[ "$arg" == *:* ]]; then
        # Parse directory:flags syntax
        dir="${arg%%:*}"
        flags="${arg#*:}"
        # Remove leading whitespace from flags
        flags=$(echo "$flags" | sed 's/^[[:space:]]*//')
        # Normalize directory name: resolve to relative path from CWD
        # This handles both "data" and "./data" formats
        debug "Parsing directory flag - dir='$dir', flags='$flags', CWD='$CWD'"
        if [ -e "$dir" ]; then
            normalized_dir=$(realpath --relative-to="$CWD" "$dir" 2>/dev/null || echo "$dir")
            # Normalize: if relative path is ".", use empty string; otherwise use the relative path
            if [ "$normalized_dir" = "." ]; then
                normalized_dir=""
            fi
            debug "Directory exists - normalized_dir='$normalized_dir', storing flags"
            # Store with normalized name, but also store with original name as fallback
            DIR_FLAGS_MAP["$normalized_dir"]="$flags"
            DIR_FLAGS_MAP["$dir"]="$flags"
            debug "Stored DIR_FLAGS_MAP['$normalized_dir']='$flags' and DIR_FLAGS_MAP['$dir']='$flags'"
        else
            # Directory doesn't exist yet, store as-is (will be checked during recursion)
            debug "Directory doesn't exist yet - storing as-is: DIR_FLAGS_MAP['$dir']='$flags'"
            DIR_FLAGS_MAP["$dir"]="$flags"
        fi
        # Also add the directory itself as a target if it exists
        if [ -d "$dir" ]; then
            explicit_target_dirs+=("$dir")
        fi
    else
        explicit_target_dirs+=("$arg")
    fi
done

debug "After parsing arguments - explicit_target_dirs=(${explicit_target_dirs[*]}), root_dot_arg_present=$root_dot_arg_present"
if [ "$DEBUG" = "true" ]; then
    debug "Final DIR_FLAGS_MAP contents:"
    for key in "${!DIR_FLAGS_MAP[@]}"; do
        debug "  DIR_FLAGS_MAP['$key']='${DIR_FLAGS_MAP[$key]}'"
    done
fi

# If no arguments provided, show current directory
if [ ${#explicit_target_dirs[@]} -eq 0 ] && [ "$root_dot_arg_present" = "false" ]; then
    echo "./"
    print_children_of_path "." "" "$GIT_ROOT" "" "" "0" "false" "" "0"
    exit 0
fi

if [ "$root_dot_arg_present" = "true" ] && [ ${#explicit_target_dirs[@]} -eq 0 ]; then
    echo "./"
    print_children_of_path "." "" "$GIT_ROOT" "" "" "0" "false" "" "0"
    exit 0
fi

if [ "$root_dot_arg_present" = "false" ]; then
    for dir_path in "${explicit_target_dirs[@]}"; do
        if [ -d "$dir_path" ]; then
            echo "${dir_path}/"
            print_children_of_path "$dir_path" "" "$GIT_ROOT" "" "" "0" "false" "" "0"
        else
            echo "Error: Path '$dir_path' does not exist or is not a directory. Skipping." >&2
        fi
    done
    exit 0
fi

if [ "$root_dot_arg_present" = "true" ] && [ ${#explicit_target_dirs[@]} -gt 0 ]; then
    echo "./"
    explicit_dirs_str_for_func="${explicit_target_dirs[*]}"
    print_children_of_path "." "" "$GIT_ROOT" "$explicit_dirs_str_for_func" "" "0" "false" "" "0"
    exit 0
fi
