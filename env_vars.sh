# shellcheck disable=SC1091
_env_vars_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -f "$_env_vars_script_dir/logging.sh" ]] && source "$_env_vars_script_dir/logging.sh"
unset _env_vars_script_dir

if ! declare -F log_error >/dev/null 2>&1; then
    log_success() { printf '[SUCCESS] %s\n' "$*" >&2; }
    log_warn() { printf '[WARN] %s\n' "$*" >&2; }
    log_error() { printf '[ERROR] %s\n' "$*" >&2; }
    log_info() { printf '[INFO] %s\n' "$*" >&2; }
fi


# Prints 1-based line number of first line whose key is KEY (prefix KEY=), CRLF-safe.
_env_first_assignment_line() {
    local key="$1"
    local file="$2"
    local nr=0
    local line stripped
    while IFS= read -r line || [ -n "$line" ]; do
        nr=$((nr + 1))
        stripped="${line%%$'\r'}"
        case "$stripped" in
            "${key}="*) printf '%s' "$nr"; return 0 ;;
        esac
    done <"$file"
    return 1
}


# Prints line numbers (one per line) for every KEY= assignment; exit 1 if KEY appears more than once.
_env_find_duplicate_lines() {
    local key="$1"
    local file="$2"
    local nr=0
    local line stripped found=0

    while IFS= read -r line || [ -n "$line" ]; do
        nr=$((nr + 1))
        stripped="${line%%$'\r'}"
        case "$stripped" in
            "${key}="*)
                printf '%s\n' "$nr"
                found=$((found + 1))
                ;;
        esac
    done <"$file"

    [[ $found -gt 1 ]] && return 1
    return 0
}


envcheck() {
    local var_name="${1-}"       # first arg, default empty
    local env_file=".env"
    local env_file_abs

    # Resolve absolute path safely
    if command -v realpath >/dev/null 2>&1; then
        env_file_abs=$(realpath "$env_file" 2>/dev/null || echo "$PWD/$env_file")
    else
        env_file_abs="$PWD/$env_file"
    fi

    # Show help if requested or no argument provided
    if [[ -z "$var_name" || "$var_name" == "--help" ]]; then
        cat <<'EOF'
Usage: envcheck VAR_NAME

Checks if VAR_NAME is set in the .env file at the current directory.
Prints the variable's value if found, or a warning if missing.
EOF
        return 0
    fi

    # Warn if .env is missing
    if [[ ! -f "$env_file" ]]; then
        log_warn ".env file not found at $env_file_abs"
        return 0
    fi

    # Pure Bash read loop (handles CRLF safely)
    local line
    local found=0
    while IFS='=' read -r key value || [ -n "$key" ]; do
        key="${key%%[[:space:]]*}"          # trim any trailing whitespace
        key="${key%%$'\r'}"                  # remove CR if present
        value="${value%%$'\r'}"              # remove CR if present
        if [[ "$key" == "$var_name" ]]; then
            log_success "Found: $key=$value ($env_file_abs)"
            found=1
            break
        fi
    done < "$env_file"

    if [[ $found -eq 0 ]]; then
        log_warn "Environment variable '$var_name' was NOT found in $env_file_abs"
    fi
}


# Prints a random URL-ish secret to stdout (no trailing newline). Default length 24.
env_gen_value() {
    local num_chars="${1:-24}"

    if [[ ! "$num_chars" =~ ^[1-9][0-9]*$ ]]; then
        log_error "env_gen_value: invalid length '$num_chars' (use a positive integer)"
        return 1
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        log_error "env_gen_value: openssl not found in PATH"
        return 1
    fi

    local rand_value
    rand_value=$(
        openssl rand -base64 $((num_chars * 3 / 4 + 2)) |
            tr -d '\n\r=+/' |
            head -c "$num_chars"
    ) || {
        log_error "env_gen_value: openssl/tr/head pipeline failed"
        return 1
    }

    rand_value="${rand_value//$'\n'/}"
    rand_value="${rand_value//$'\r'/}"
    if [[ "$rand_value" == *$'\n'* || "$rand_value" == *$'\r'* ]]; then
        log_error "newline detected in secret generation after sanitization"
        return 1
    fi

    if [[ -z "$rand_value" ]]; then
        log_error "env_gen_value: generated empty secret"
        return 1
    fi

    printf '%s' "$rand_value"
}


# Sets VAR_NAME=VALUE in ./.env (creates file if missing). Replaces the first line
# whose key matches; drops further duplicate lines for that key only after write —
# duplicate assignments for VAR_NAME before write cause hard failure (strict invariant).
# New keys append at end. Value must be single-line at write time.
# Uses flock on .env.lock when available; otherwise concurrent writers are not serialized.
env_set() {
    local var_name="$1"
    local value="$2"
    local env_file=".env"
    local env_file_abs
    local lockfile="${env_file}.lock"

    if command -v realpath >/dev/null 2>&1; then
        env_file_abs=$(realpath "$env_file" 2>/dev/null || echo "$PWD/$env_file")
    else
        env_file_abs="$PWD/$env_file"
    fi

    if [[ -z "$var_name" ]]; then
        log_error "env_set: missing VAR_NAME (usage: env_set VAR_NAME VALUE)"
        return 1
    fi

    value="${value//$'\n'/}"
    value="${value//$'\r'/}"
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        log_error "refusing to write .env: newline or carriage return in value for '$var_name'"
        return 1
    fi

    # Strict: at most one assignment per key before mutation (fail fast if violated).
    local dup_capture ln ctx
    if [[ -f "$env_file" ]]; then
        if ! dup_capture=$(_env_find_duplicate_lines "$var_name" "$env_file"); then
            log_error "DUPLICATE KEY DETECTED: '$var_name' appears more than once in ${env_file_abs}"
            while IFS= read -r ln || [[ -n "$ln" ]]; do
                [[ -z "$ln" ]] && continue
                ctx=$(sed -n "${ln}p" "$env_file" 2>/dev/null || true)
                log_error "  line ${ln}: ${ctx}"
            done <<<"$dup_capture"
            return 1
        fi
    fi

    [[ ! -f "$env_file" ]] && touch "$env_file"

    local had_key=0
    if _env_first_assignment_line "$var_name" "$env_file" >/dev/null 2>&1; then
        had_key=1
    fi

    local flock_ok=0
    command -v flock >/dev/null 2>&1 && flock_ok=1

    local ec=0

    # flock + FD only inside subshell — avoids hijacking the caller's FD 200 (fixed broken shells).
    # Exit codes from rewrite subshell (for actionable logs): 80=flock 81=mktemp 82=tmp write 83=mv
    if [[ $flock_ok -eq 1 ]]; then
        (
            flock 200 || exit 80
            tmp_file=$(mktemp) || exit 81
            trap 'rm -f "$tmp_file"' EXIT INT TERM
            {
                replaced=0
                while IFS= read -r line || [ -n "$line" ]; do
                    stripped="${line%%$'\r'}"
                    case "$stripped" in
                        "${var_name}="*)
                            if [[ $replaced -eq 0 ]]; then
                                printf '%s=%s\n' "$var_name" "$value"
                                replaced=1
                            fi
                            ;;
                        *)
                            printf '%s\n' "$line"
                            ;;
                    esac
                done <"$env_file"
                if [[ $replaced -eq 0 ]]; then
                    printf '%s=%s\n' "$var_name" "$value"
                fi
            } >"$tmp_file" || exit 82
            command mv -f "$tmp_file" "$env_file" || exit 83
            trap - EXIT INT TERM
        ) 200>"$lockfile" || ec=$?
    else
        # Without flock, concurrent env_set/envgen calls may interleave (e.g. Git Bash, some macOS).
        (
            tmp_file=$(mktemp) || exit 81
            trap 'rm -f "$tmp_file"' EXIT INT TERM
            {
                replaced=0
                while IFS= read -r line || [ -n "$line" ]; do
                    stripped="${line%%$'\r'}"
                    case "$stripped" in
                        "${var_name}="*)
                            if [[ $replaced -eq 0 ]]; then
                                printf '%s=%s\n' "$var_name" "$value"
                                replaced=1
                            fi
                            ;;
                        *)
                            printf '%s\n' "$line"
                            ;;
                    esac
                done <"$env_file"
                if [[ $replaced -eq 0 ]]; then
                    printf '%s=%s\n' "$var_name" "$value"
                fi
            } >"$tmp_file" || exit 82
            command mv -f "$tmp_file" "$env_file" || exit 83
            trap - EXIT INT TERM
        ) || ec=$?
    fi

    if [[ $ec -ne 0 ]]; then
        case $ec in
            80)
                log_error "could not lock ${lockfile} (flock failed). On Git Bash / MSYS, flock is often broken or unsupported; use WSL/Linux on the VPS, or run without a usable flock in PATH."
                ;;
            81)
                log_error "mktemp failed while preparing .env rewrite (permissions or TMPDIR unset/invalid?)"
                ;;
            82)
                log_error "failed writing temp copy of .env (disk full, quota, or read error on ${env_file_abs}?)"
                ;;
            83)
                log_error "mv temp -> ${env_file_abs} failed (file open elsewhere, permissions, antivirus, or rename rules on this OS)."
                ;;
            *)
                log_error "failed to write ${env_file_abs} (unexpected subshell exit ${ec})"
                ;;
        esac
        return 1
    fi

    if [[ -z "${ENV_VARS_QUIET_ENV_SET:-}" ]]; then
        local assign_ln
        assign_ln=$(_env_first_assignment_line "$var_name" "$env_file") || assign_ln='?'
        if [[ $had_key -eq 1 ]]; then
            log_success "Replaced env var $var_name in $env_file_abs on line $assign_ln"
        else
            log_success "Added env var $var_name to $env_file_abs on line $assign_ln"
        fi
    fi
}


envgen() {
    local var_name="$1"
    local num_chars="${2:-24}"
    local env_file=".env"
    local env_file_abs

    if command -v realpath >/dev/null 2>&1; then
        env_file_abs=$(realpath "$env_file" 2>/dev/null || echo "$PWD/$env_file")
    else
        env_file_abs="$PWD/$env_file"
    fi

    if [[ -z "$var_name" || "$var_name" == "--help" ]]; then
        cat <<'EOF'
Usage: env_gen VAR_NAME [NUM_CHARS]

Generates a random string of NUM_CHARS (default 24) for VAR_NAME in the .env file
in the current directory. If VAR_NAME already exists, its value is replaced.

Examples:
  env_gen API_KEY
      # Adds or updates API_KEY with a new random 24-character value in .env

  env_gen JWT_SECRET 40
      # Adds/updates JWT_SECRET with a 40-character random value

Primitives:
  env_gen_value [NUM_CHARS]   # print random secret only (stdout)
  env_set VAR_NAME VALUE      # write assignment to .env

- .env will be created if it does not exist.
- Random values use openssl and are URL-safe (=/+ characters removed).
- Duplicate assignments for the same key cause env_set/envgen to fail (merge manually first).

EOF
        return 0
    fi

    local existed=0
    local line
    if [[ -f "$env_file" ]]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%%$'\r'}"
            case "$line" in
                "${var_name}="*) existed=1; break ;;
            esac
        done < "$env_file"
    fi

    local rand_value
    rand_value=$(env_gen_value "$num_chars") || {
        log_error "envgen: secret generation failed for $var_name"
        return 1
    }

    ENV_VARS_QUIET_ENV_SET=1 env_set "$var_name" "$rand_value" || {
        log_error "envgen: could not write $var_name to $env_file_abs"
        return 1
    }

    local assign_ln
    assign_ln=$(_env_first_assignment_line "$var_name" "$env_file") || assign_ln='?'

    if [[ $existed -eq 1 ]]; then
        log_success "Replaced env var $var_name (${#rand_value} chars) in $env_file_abs on line $assign_ln"
    else
        log_success "Added env var $var_name (${#rand_value} chars) to $env_file_abs on line $assign_ln"
    fi
}
