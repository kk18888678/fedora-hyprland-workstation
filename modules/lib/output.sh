#!/usr/bin/env bash

# Output and logging helpers.

INSTALLER_LOG_TEE_PID=""
INSTALLER_LOG_STDOUT_FD=""
INSTALLER_LOG_STDERR_FD=""

info() {
    printf 'INFO: %s\n' "$*"
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

error() {
    printf 'ERROR: %s\n' "$*" >&2
}

# Keep the installer log pipeline alive until the final summary has been
# written, then restore the caller's descriptors and wait for tee to drain.
# Bash does not reliably wait for process substitutions before a surrounding
# shell removes their output directory, so leaving this to shell shutdown can
# lose the tail of a run (and can turn a harmless logging race into SIGPIPE).
start_installer_logging() {
    local log_file="${INSTALL_LOG_FILE:-}"

    [[ -n "$log_file" && "$log_file" == /* && "$log_file" != "/" ]] || {
        error "Installer log path is not a valid absolute path."
        return 1
    }
    [[ -f "$log_file" && ! -L "$log_file" ]] || {
        error "Installer log file is missing or is a symlink: $log_file"
        return 1
    }
    command_exists tee || {
        error "Required logging utility 'tee' was not found."
        return 1
    }

    if ! exec {INSTALLER_LOG_STDOUT_FD}>&1; then
        error "Could not preserve installer stdout for logging."
        return 1
    fi

    if ! exec {INSTALLER_LOG_STDERR_FD}>&2; then
        exec {INSTALLER_LOG_STDOUT_FD}>&- 2>/dev/null || true
        INSTALLER_LOG_STDOUT_FD=""
        error "Could not preserve installer stderr for logging."
        return 1
    fi

    # The process substitution inherits the preserved original stdout, so tee
    # continues to display installer output while appending the same bytes to
    # the already-created, user-owned log file.
    if ! exec > >(tee -a "$log_file") 2>&1; then
        exec 1>&"$INSTALLER_LOG_STDOUT_FD" 2>&"$INSTALLER_LOG_STDERR_FD" || true
        exec {INSTALLER_LOG_STDOUT_FD}>&- 2>/dev/null || true
        exec {INSTALLER_LOG_STDERR_FD}>&- 2>/dev/null || true
        INSTALLER_LOG_STDOUT_FD=""
        INSTALLER_LOG_STDERR_FD=""
        error "Could not start installer logging."
        return 1
    fi

    INSTALLER_LOG_TEE_PID="$!"
    [[ "$INSTALLER_LOG_TEE_PID" =~ ^[0-9]+$ ]] || {
        stop_installer_logging || true
        return 1
    }
}

stop_installer_logging() {
    local tee_pid="${INSTALLER_LOG_TEE_PID:-}"
    local stdout_fd="${INSTALLER_LOG_STDOUT_FD:-}"
    local stderr_fd="${INSTALLER_LOG_STDERR_FD:-}"
    local restore_status=0
    local tee_status=0

    [[ -n "$stdout_fd" && -n "$stderr_fd" ]] || return 0

    # Restoring both descriptors closes the shell's write ends of the
    # process-substitution pipe. Only then can tee observe EOF and be waited
    # on without deadlocking.
    if ! exec 1>&"$stdout_fd" 2>&"$stderr_fd"; then
        restore_status=1
    fi
    exec {stdout_fd}>&- 2>/dev/null || restore_status=1
    exec {stderr_fd}>&- 2>/dev/null || restore_status=1

    INSTALLER_LOG_STDOUT_FD=""
    INSTALLER_LOG_STDERR_FD=""
    INSTALLER_LOG_TEE_PID=""

    if [[ -n "$tee_pid" ]]; then
        if wait "$tee_pid"; then
            :
        else
            tee_status=$?
        fi
    fi

    if (( restore_status != 0 )); then
        error "Could not restore installer output descriptors after logging."
        return 1
    fi

    if (( tee_status != 0 )); then
        error "Installer log pipeline exited with status ${tee_status}."
        return "$tee_status"
    fi

    return 0
}

die() {
    error "$*"
    exit 1
}
