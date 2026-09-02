#!/usr/bin/env bash

# Persistent installer journal.
#
# Location: /var/lib/fedora-hyprland-workstation
#
# This is observability and crash leftovers, not configuration.
# Re-running the installer always reconciles from Git.

INSTALLER_STATE_ROOT="/var/lib/fedora-hyprland-workstation"

init_installer_state() {
    local now

    now="$(date +%Y%m%d-%H%M%S)"

    sudo install -d -m 0755 "$INSTALLER_STATE_ROOT"

    # User-owned so the non-root installer can write logs without
    # piping every line through sudo.
    sudo install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" \
        "$INSTALLER_STATE_ROOT/state" \
        "$INSTALLER_STATE_ROOT/failures" \
        "$INSTALLER_STATE_ROOT/generations" \
        "$INSTALLER_STATE_ROOT/logs"

    INSTALL_LOG_FILE="$INSTALLER_STATE_ROOT/logs/install-${now}.log"
    INSTALL_RUN_ID="$now"

    : >"$INSTALL_LOG_FILE"

    cat >"$INSTALLER_STATE_ROOT/state/last-run" <<EOF
run_id=${INSTALL_RUN_ID}
profile=${PROFILE}
user=${TARGET_USER}
started_at=$(date --iso-8601=seconds)
status=running
EOF

    # generations/ is reserved for a future pre-activation Btrfs snapshot.
    if [[ ! -f "$INSTALLER_STATE_ROOT/generations/README" ]]; then
        cat >"$INSTALLER_STATE_ROOT/generations/README" <<'EOF'
Reserved for future pre-activation generations (for example a Btrfs snapshot).
The Git repository remains the desired-state source of truth.
EOF
    fi

    info "Installer log: $INSTALL_LOG_FILE"
}

journal_stage() {
    local stage="$1"
    local status="$2"

    printf '%s %s %s\n' "$(date --iso-8601=seconds)" "$stage" "$status" \
        >>"$INSTALLER_STATE_ROOT/state/journal" 2>/dev/null || true
}

write_failure_note() {
    local stage="$1"
    local message="$2"
    local file

    file="$INSTALLER_STATE_ROOT/failures/${INSTALL_RUN_ID:-unknown}-${stage}.txt"

    {
        printf 'stage=%s\n' "$stage"
        printf 'time=%s\n' "$(date --iso-8601=seconds)"
        printf 'message=%s\n' "$message"
        printf 'rerun=safe\n'
    } >"$file"
}

finalize_installer_state() {
    local exit_code="${1:-1}"

    if [[ -n "${INSTALLER_STATE_ROOT:-}" && -d "${INSTALLER_STATE_ROOT}/state" ]]; then
        cat >"$INSTALLER_STATE_ROOT/state/last-run" <<EOF
run_id=${INSTALL_RUN_ID:-unknown}
profile=${PROFILE:-unknown}
user=${TARGET_USER:-unknown}
finished_at=$(date --iso-8601=seconds)
status=${exit_code}
activation_blocked=${ACTIVATION_BLOCKED:-0}
EOF
    fi

    release_installer_lock
}

INSTALLER_LOCK_FD=200
INSTALLER_LOCK_FILE=""

get_installer_lock_path() {
    local uid="${OVERRIDE_EUID:-${EUID:-$(id -u)}}"
    local runtime_dir=""

    # 1. Prefer verified XDG_RUNTIME_DIR if safe and non-symlink
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" && ! -L "${XDG_RUNTIME_DIR}" && -w "${XDG_RUNTIME_DIR}" ]]; then
        runtime_dir="${XDG_RUNTIME_DIR}"
    # 2. Prefer standard systemd /run/user/$uid if safe and non-symlink
    elif [[ -d "/run/user/${uid}" && ! -L "/run/user/${uid}" && -w "/run/user/${uid}" ]]; then
        runtime_dir="/run/user/${uid}"
    fi

    if [[ -n "$runtime_dir" ]]; then
        printf '%s/fedora-hyprland-workstation.lock\n' "$runtime_dir"
        return 0
    fi

    # 3. Fallback: secure, private per-user directory in /tmp
    local fallback_base="/tmp"
    local fallback_dir="${fallback_base}/.fhw-lock-${uid}"

    if [[ -L "$fallback_dir" ]]; then
        error "Insecure symlink detected at lock directory: $fallback_dir"
        return 1
    fi

    if [[ ! -d "$fallback_dir" ]]; then
        if ! mkdir -m 0700 "$fallback_dir" 2>/dev/null; then
            error "Failed to create secure lock directory: $fallback_dir"
            return 1
        fi
    fi

    # Verify directory type and reject symlinks
    if [[ -L "$fallback_dir" || ! -d "$fallback_dir" ]]; then
        error "Lock directory $fallback_dir is invalid or a symlink."
        return 1
    fi

    # Ensure permissions are strictly private (0700)
    chmod 0700 "$fallback_dir" 2>/dev/null || true

    # Verify directory ownership if stat is available
    if command_exists stat; then
        local dir_owner
        dir_owner="$(stat -c '%u' "$fallback_dir" 2>/dev/null || true)"
        if [[ -n "$dir_owner" && "$dir_owner" != "$uid" && "$uid" != "0" ]]; then
            error "Lock directory $fallback_dir is owned by UID $dir_owner, expected UID $uid."
            return 1
        fi
    fi

    printf '%s/installer.lock\n' "$fallback_dir"
    return 0
}

acquire_installer_lock() {
    if ! command_exists flock; then
        die "Required locking utility 'flock' was not found. Concurrency protection cannot be established; refusing to proceed."
    fi

    local lock_file
    if ! lock_file="$(get_installer_lock_path)" || [[ -z "$lock_file" ]]; then
        die "Could not determine safe lock file location. Refusing to proceed without concurrency protection."
    fi

    INSTALLER_LOCK_FILE="$lock_file"

    eval "exec ${INSTALLER_LOCK_FD}>\"\$INSTALLER_LOCK_FILE\""

    if ! flock -n "$INSTALLER_LOCK_FD"; then
        die "Another instance of the installer is currently running (locked at $INSTALLER_LOCK_FILE). Refusing concurrent execution."
    fi

    printf '%s\n' "$$" >&"$INSTALLER_LOCK_FD" 2>/dev/null || true
}

release_installer_lock() {
    if [[ -n "${INSTALLER_LOCK_FD:-}" ]]; then
        flock -u "$INSTALLER_LOCK_FD" 2>/dev/null || true
        eval "exec ${INSTALLER_LOCK_FD}>&-" 2>/dev/null || true
    fi
}


