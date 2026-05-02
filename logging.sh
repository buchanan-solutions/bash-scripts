#!/bin/bash
# debug_utils.sh
# Provides debug_print function

# log_* tag colors (stderr TTY only; respect https://no-color.org/)
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    _LOG_GREEN=$'\033[32m'
    _LOG_YELLOW=$'\033[33m'
    _LOG_RED=$'\033[31m'
    _LOG_CYAN=$'\033[36m'
    _LOG_RESET=$'\033[0m'
else
    _LOG_GREEN=''
    _LOG_YELLOW=''
    _LOG_RED=''
    _LOG_CYAN=''
    _LOG_RESET=''
fi

# Usage: debug "message"
debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo "DEBUG: $*" >&2
    fi
}

warn() {
    if [ "${WARN:-false}" = "true" ]; then
        echo "WARN: $*" >&2
    fi
}

error() {
    if [ "${ERROR:-false}" = "true" ]; then
        echo "ERROR: $*" >&2
    fi
}

info() {
    if [ "${INFO:-false}" = "true" ]; then
        echo "INFO: $*" >&2
    fi
}

# Always emitted (stderr). Use for visible CLI status when gated warn/error/info are off.
log_success() {
    printf '%s[SUCCESS]%s %s\n' "$_LOG_GREEN" "$_LOG_RESET" "$*" >&2
}

log_warn() {
    printf '%s[WARN]%s %s\n' "$_LOG_YELLOW" "$_LOG_RESET" "$*" >&2
}

log_error() {
    printf '%s[ERROR]%s %s\n' "$_LOG_RED" "$_LOG_RESET" "$*" >&2
}

log_info() {
    printf '%s[INFO]%s %s\n' "$_LOG_CYAN" "$_LOG_RESET" "$*" >&2
}