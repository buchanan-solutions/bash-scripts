#!/bin/bash
# debug_utils.sh
# Provides debug_print function

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