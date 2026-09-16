#!/usr/bin/env bash
# Idempotently add bash-scripts bootstrap sourcing to ~/.bashrc.
set -euo pipefail

BASH_SCRIPTS_BLOCK_START='# <-- bash-scripts:start -->'
BASH_SCRIPTS_BLOCK_END='# <-- bash-scripts:end -->'

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

script_dir() {
    local src="${BASH_SOURCE[0]}"
    local dir
    dir="$(cd "$(dirname "$src")" && pwd)"
    if [[ -L "$src" ]]; then
        src="$(readlink -f "$src")"
        dir="$(cd "$(dirname "$src")" && pwd)"
    fi
    printf '%s\n' "$dir"
}

INSTALL_DIR="$(script_dir)"
BASHRC="${HOME}/.bashrc"

count_fixed_matches() {
    local needle="$1" file="$2" n
    [[ -f "$file" ]] || { printf '0\n'; return 0; }
    n="$(grep -cF -- "$needle" "$file" 2>/dev/null || true)"
    printf '%s\n' "${n:-0}"
}

# Sets _BASH_SCRIPTS_BLOCK_STATE = none|present|malformed
# and _BASH_SCRIPTS_BLOCK_* line/reason details when applicable.
inspect_bash_scripts_block() {
    local file="$1"
    _BASH_SCRIPTS_BLOCK_STATE="none"
    _BASH_SCRIPTS_BLOCK_REASON=""
    _BASH_SCRIPTS_BLOCK_START_LINE=0
    _BASH_SCRIPTS_BLOCK_END_LINE=0

    [[ -f "$file" ]] || return 0

    local start_count end_count
    start_count="$(count_fixed_matches "$BASH_SCRIPTS_BLOCK_START" "$file")"
    end_count="$(count_fixed_matches "$BASH_SCRIPTS_BLOCK_END" "$file")"

    if [[ "$start_count" -eq 0 && "$end_count" -eq 0 ]]; then
        _BASH_SCRIPTS_BLOCK_STATE="none"
        return 0
    fi

    if [[ "$start_count" -ne 1 || "$end_count" -ne 1 ]]; then
        _BASH_SCRIPTS_BLOCK_STATE="malformed"
        _BASH_SCRIPTS_BLOCK_REASON="expected exactly one '$BASH_SCRIPTS_BLOCK_START' and one '$BASH_SCRIPTS_BLOCK_END' (found start=$start_count end=$end_count)"
        return 0
    fi

    _BASH_SCRIPTS_BLOCK_START_LINE="$(grep -nF -- "$BASH_SCRIPTS_BLOCK_START" "$file" | head -1 | cut -d: -f1)"
    _BASH_SCRIPTS_BLOCK_END_LINE="$(grep -nF -- "$BASH_SCRIPTS_BLOCK_END" "$file" | head -1 | cut -d: -f1)"

    if [[ "$_BASH_SCRIPTS_BLOCK_START_LINE" -ge "$_BASH_SCRIPTS_BLOCK_END_LINE" ]]; then
        _BASH_SCRIPTS_BLOCK_STATE="malformed"
        _BASH_SCRIPTS_BLOCK_REASON="start marker must appear before end marker (start=line $_BASH_SCRIPTS_BLOCK_START_LINE end=line $_BASH_SCRIPTS_BLOCK_END_LINE)"
        return 0
    fi

    _BASH_SCRIPTS_BLOCK_STATE="present"
}

die_malformed_bashrc_block() {
    die "Refusing to modify $BASHRC: bash-scripts managed block is malformed.

$_BASH_SCRIPTS_BLOCK_REASON

bash-scripts only edits the region between:
  $BASH_SCRIPTS_BLOCK_START
  $BASH_SCRIPTS_BLOCK_END

Fix or remove the broken markers manually, then rerun ./install.sh."
}

write_bash_scripts_block() {
    local file="$1"
    local interior="$2"
    local tmp
    tmp="$(mktemp)"

    inspect_bash_scripts_block "$file"
    case "$_BASH_SCRIPTS_BLOCK_STATE" in
        malformed)
            rm -f "$tmp"
            die_malformed_bashrc_block
            ;;
        none)
            rm -f "$tmp"
            if [[ -f "$file" && -s "$file" ]]; then
                local last_char
                last_char="$(tail -c 1 "$file" 2>/dev/null || true)"
                if [[ -n "$last_char" && "$last_char" != $'\n' ]]; then
                    printf '\n' >>"$file"
                fi
                printf '\n' >>"$file"
            else
                mkdir -p "$(dirname "$file")"
                : >"$file"
            fi
            {
                printf '%s\n' "$BASH_SCRIPTS_BLOCK_START"
                printf '%s\n' "$interior"
                printf '%s\n' "$BASH_SCRIPTS_BLOCK_END"
            } >>"$file"
            ;;
        present)
            {
                if [[ "$_BASH_SCRIPTS_BLOCK_START_LINE" -gt 1 ]]; then
                    head -n "$((_BASH_SCRIPTS_BLOCK_START_LINE - 1))" "$file"
                fi
                printf '%s\n' "$BASH_SCRIPTS_BLOCK_START"
                printf '%s\n' "$interior"
                printf '%s\n' "$BASH_SCRIPTS_BLOCK_END"
                tail -n "+$((_BASH_SCRIPTS_BLOCK_END_LINE + 1))" "$file"
            } >"$tmp"
            cat "$tmp" >"$file"
            rm -f "$tmp"
            ;;
    esac
}

read_bash_scripts_block_interior() {
    local file="$1"
    inspect_bash_scripts_block "$file"
    [[ "$_BASH_SCRIPTS_BLOCK_STATE" == "present" ]] || return 1
    local start="$_BASH_SCRIPTS_BLOCK_START_LINE" end="$_BASH_SCRIPTS_BLOCK_END_LINE"
    if [[ "$((end - start))" -le 1 ]]; then
        return 0
    fi
    sed -n "$((start + 1)),$((end - 1))p" "$file"
}

bootstrap_source_line() {
    printf 'if [ -f "%s/bootstrap.sh" ]; then source "%s/bootstrap.sh"; fi' "$INSTALL_DIR" "$INSTALL_DIR"
}

bootstrap_already_loaded_from_checkout() {
    [[ -n "${BASE_DIR:-}" ]] || return 1
    local real_base real_install
    real_base="$(readlink -f "$BASE_DIR" 2>/dev/null || printf '%s' "$BASE_DIR")"
    real_install="$(readlink -f "$INSTALL_DIR" 2>/dev/null || printf '%s' "$INSTALL_DIR")"
    [[ "$real_base" == "$real_install" ]]
}

prompt_yes_default() {
    local prompt="$1"
    local answer=""
    if [[ ! -t 0 ]]; then
        die "stdin is non-interactive; refusing to modify shell configuration automatically.
Run ./install.sh from a terminal, or pass --yes."
    fi
    printf '%s' "$prompt" >&2
    read -r answer || true
    case "${answer:-Y}" in
        ''|Y|y|yes|YES|Yes) return 0 ;;
        n|N|no|NO|No) return 1 ;;
        *) die "unrecognized answer '$answer' (expected Y or n)" ;;
    esac
}

show_help() {
    cat <<'EOF'
bash-scripts install — add bootstrap sourcing to ~/.bashrc

Usage:
  ./install.sh [--yes]

Options:
  --yes, -y   Apply changes without prompting (requires a TTY for first install
              unless a managed block already exists)

The installer writes or updates a managed block in ~/.bashrc between:
  # <-- bash-scripts:start -->
  # <-- bash-scripts:end -->

Re-running install.sh is safe: it updates the block if the checkout moved,
or reports success when already configured.
EOF
}

install_bootstrap_registration() {
    local assume_yes="${1:-0}"
    local source_line
    source_line="$(bootstrap_source_line)"

    [[ -f "${INSTALL_DIR}/bootstrap.sh" ]] \
        || die "bootstrap.sh not found in checkout: $INSTALL_DIR"

    [[ -n "${BASH_VERSION:-}" ]] \
        || die "Installation currently supports Bash only (BASH_VERSION is unset).
Source bootstrap.sh manually, or rerun from Bash."

    case "${SHELL:-}" in
        ''|*/bash) ;;
        *)
            die "Installation currently supports Bash only (SHELL=${SHELL}).
bash-scripts manages a block in ~/.bashrc and will not edit other shell rc files."
            ;;
    esac

    info "bash-scripts installation"
    info ""
    info "  · checkout: $INSTALL_DIR"
    info "  · target:   $BASHRC"

    inspect_bash_scripts_block "$BASHRC"
    case "$_BASH_SCRIPTS_BLOCK_STATE" in
        malformed)
            die_malformed_bashrc_block
            ;;
        present)
            local interior
            interior="$(read_bash_scripts_block_interior "$BASHRC" || true)"
            if [[ "$interior" == "$source_line" ]]; then
                info "  ✓ managed block already sources this checkout"
                return 0
            fi
            write_bash_scripts_block "$BASHRC" "$source_line"
            info "  ✓ updated managed block"
            info "  · run: source $BASHRC"
            return 0
            ;;
        none)
            if bootstrap_already_loaded_from_checkout; then
                info "  · bootstrap already loaded in this shell from this checkout"
            else
                info "  · bootstrap is not currently loaded in this shell"
            fi
            info ""
            if [[ "$assume_yes" -eq 0 ]] && ! prompt_yes_default "Add bash-scripts to ~/.bashrc? [Y/n]: "; then
                info "Installation cancelled. No shell configuration was changed."
                return 0
            fi
            write_bash_scripts_block "$BASHRC" "$source_line"
            info "  ✓ wrote managed block"
            info "  · run: source $BASHRC"
            return 0
            ;;
    esac
}

main() {
    local assume_yes=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                return 0
                ;;
            -y|--yes)
                assume_yes=1
                shift
                ;;
            *)
                die "unknown argument: $1
usage: ./install.sh [--yes]"
                ;;
        esac
    done

    install_bootstrap_registration "$assume_yes"
    info ""
    info "bash-scripts installation complete."
}

main "$@"
