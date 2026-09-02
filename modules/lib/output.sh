#!/usr/bin/env bash

# Output and logging helpers.

info() {
    printf 'INFO: %s\n' "$*"
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

error() {
    printf 'ERROR: %s\n' "$*" >&2
}

die() {
    error "$*"
    exit 1
}
