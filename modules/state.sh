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
}
