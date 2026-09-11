#!/usr/bin/env bash

# Persistent installer journal.
#
# Location: /var/lib/fedora-hyprland-workstation
#
# This is observability and crash leftovers, not configuration.
# Re-running the installer always reconciles from Git.

INSTALLER_STATE_ROOT="/var/lib/fedora-hyprland-workstation"

state_file_target_is_safe() {
    local destination="$1"

    [[ -n "$destination" && "$destination" == "$INSTALLER_STATE_ROOT"/* ]] || return 1
    [[ ! -L "$destination" ]] || return 1

    if declare -F validate_mutation_path >/dev/null 2>&1; then
        validate_mutation_path "$(dirname -- "$destination")" || return 1
    fi
}

write_installer_state_file() {
    local destination="$1"
    local content="$2"
    local destination_dir
    local temporary_file

    state_file_target_is_safe "$destination" || return 1
    destination_dir="$(dirname -- "$destination")"
    temporary_file="$(mktemp "$destination_dir/.fhw-state.XXXXXX")" || return 1

    if ! printf '%s' "$content" >"$temporary_file"; then
        rm -f -- "$temporary_file"
        return 1
    fi

    if ! mv -T -- "$temporary_file" "$destination"; then
        rm -f -- "$temporary_file"
        return 1
    fi
}

init_installer_state() {
    local now
    local target_uid="${TARGET_UID:-}"
    local target_gid="${TARGET_GID:-}"
    local last_run_file="$INSTALLER_STATE_ROOT/state/last-run"
    local generations_readme="$INSTALLER_STATE_ROOT/generations/README"

    # Validate every installer-owned state path before any privileged mkdir.
    # This rejects a pre-existing symlink at the root or one of its managed
    # subdirectories instead of allowing install(1) to follow it.
    if declare -F validate_mutation_path >/dev/null 2>&1; then
        validate_mutation_path "$INSTALLER_STATE_ROOT" ||
            die "Installer state root path is unsafe."
        validate_mutation_path "$INSTALLER_STATE_ROOT/state" ||
            die "Installer state directory path is unsafe."
        validate_mutation_path "$INSTALLER_STATE_ROOT/failures" ||
            die "Installer failure directory path is unsafe."
        validate_mutation_path "$INSTALLER_STATE_ROOT/generations" ||
            die "Installer generation directory path is unsafe."
        validate_mutation_path "$INSTALLER_STATE_ROOT/logs" ||
            die "Installer log directory path is unsafe."
    fi

    [[ ! -L "$last_run_file" && ! -L "$generations_readme" ]] ||
        die "Installer state contains a symlinked managed file; refusing to write state."

    if [[ -z "$target_uid" ]]; then
        target_uid="$(id -u "$TARGET_USER" 2>/dev/null || true)"
    fi
    if [[ -z "$target_gid" ]]; then
        target_gid="$(id -g "$TARGET_USER" 2>/dev/null || true)"
    fi
    [[ "$target_uid" =~ ^[0-9]+$ && "$target_gid" =~ ^[0-9]+$ ]] ||
        die "Could not determine numeric ownership for installer state."

    now="$(date +%Y%m%d-%H%M%S)"

    sudo install -d -m 0755 "$INSTALLER_STATE_ROOT"

    # User-owned so the non-root installer can write logs without
    # piping every line through sudo.
    sudo install -d -m 0755 -o "$target_uid" -g "$target_gid" \
        "$INSTALLER_STATE_ROOT/state" \
        "$INSTALLER_STATE_ROOT/failures" \
        "$INSTALLER_STATE_ROOT/generations" \
        "$INSTALLER_STATE_ROOT/logs"

    if ! INSTALL_LOG_FILE="$(mktemp "$INSTALLER_STATE_ROOT/logs/install-${now}-XXXXXX.log")"; then
        die "Could not create a secure installer log file."
    fi
    INSTALL_RUN_ID="$now"

    if ! write_installer_state_file "$last_run_file" "run_id=${INSTALL_RUN_ID}
profile=${PROFILE}
user=${TARGET_USER}
started_at=$(date --iso-8601=seconds)
status=running
"; then
        die "Could not initialize installer state at $last_run_file."
    fi

    # generations/ is reserved for a future pre-activation Btrfs snapshot.
    if [[ ! -f "$generations_readme" ]]; then
        if ! write_installer_state_file "$generations_readme" 'Reserved for future pre-activation generations (for example a Btrfs snapshot).
The Git repository remains the desired-state source of truth.
'; then
            die "Could not initialize installer generation state at $generations_readme."
        fi
    fi

    info "Installer log: $INSTALL_LOG_FILE"
}

journal_stage() {
    local stage="$1"
    local status="$2"
    local journal_file="$INSTALLER_STATE_ROOT/state/journal"
    local journal_dir
    local temporary_file

    state_file_target_is_safe "$journal_file" || return 0
    if [[ -e "$journal_file" && ( ! -f "$journal_file" || -L "$journal_file" ) ]]; then
        return 0
    fi

    journal_dir="$(dirname -- "$journal_file")"
    temporary_file="$(mktemp "$journal_dir/.journal.XXXXXX" 2>/dev/null)" || return 0

    if [[ -f "$journal_file" ]] && ! cp -- "$journal_file" "$temporary_file"; then
        rm -f -- "$temporary_file"
        return 0
    fi

    if ! printf '%s %s %s\n' "$(date --iso-8601=seconds)" "$stage" "$status" \
        >>"$temporary_file"; then
        rm -f -- "$temporary_file"
        return 0
    fi

    if ! mv -T -- "$temporary_file" "$journal_file"; then
        rm -f -- "$temporary_file"
    fi
}

write_failure_note() {
    local stage="$1"
    local message="$2"
    local file

    file="$INSTALLER_STATE_ROOT/failures/${INSTALL_RUN_ID:-unknown}-${stage}.txt"

    local content
    content="$(printf 'stage=%s\ntime=%s\nmessage=%s\nrerun=safe\n' \
        "$stage" "$(date --iso-8601=seconds)" "$message")"

    write_installer_state_file "$file" "$content" ||
        error "Could not write installer failure note: $file"
}

finalize_installer_state() {
    local exit_code="${1:-1}"
    local last_run_file="$INSTALLER_STATE_ROOT/state/last-run"

    if [[ -n "${INSTALLER_STATE_ROOT:-}" && -d "${INSTALLER_STATE_ROOT}/state" ]]; then
        if ! write_installer_state_file "$last_run_file" "run_id=${INSTALL_RUN_ID:-unknown}
profile=${PROFILE:-unknown}
user=${TARGET_USER:-unknown}
finished_at=$(date --iso-8601=seconds)
status=${exit_code}
activation_blocked=${ACTIVATION_BLOCKED:-0}
"; then
            error "Could not finalize installer state at $INSTALLER_STATE_ROOT/state/last-run."
        fi
    fi

    release_installer_lock
}

# Bash allocates a private descriptor for the lock at acquisition time.  Do
# not use eval for redirections: the lock path is validated separately, and
# descriptor management should remain data-only.
INSTALLER_LOCK_FD=""
INSTALLER_LOCK_FILE=""

validate_lock_directory() {
    local candidate="$1"
    local uid="$2"

    [[ -n "$candidate" ]] || return 1

    # 1. Absolute path check
    [[ "$candidate" == /* ]] || {
        warn "Lock directory candidate is not an absolute path: $candidate"
        return 1
    }

    # 2. Must exist and be a real directory
    [[ -d "$candidate" ]] || return 1

    # 3. Must not be a symlink
    [[ ! -L "$candidate" ]] || {
        warn "Lock directory candidate is a symlink: $candidate"
        return 1
    }

    # 4. Must be writable by current process
    [[ -w "$candidate" ]] || {
        warn "Lock directory candidate is not writable: $candidate"
        return 1
    }

    # 5. Metadata verification requires stat
    if ! command_exists stat; then
        error "Required metadata utility 'stat' was not found; cannot verify lock directory safety."
        return 1
    fi

    # 6. Ownership verification
    local owner
    owner="$(stat -c '%u' "$candidate" 2>/dev/null || true)"
    if [[ -z "$owner" ]]; then
        warn "Could not determine owner for lock directory candidate: $candidate"
        return 1
    fi

    if [[ "$owner" != "$uid" && "$uid" != "0" ]]; then
        warn "Lock directory candidate $candidate is owned by UID $owner, expected UID $uid."
        return 1
    fi

    # 7. Permission policy verification (reject group/world write)
    local perm
    perm="$(stat -c '%a' "$candidate" 2>/dev/null || true)"
    if [[ -z "$perm" ]]; then
        warn "Could not determine permissions for lock directory candidate: $candidate"
        return 1
    fi

    local mode_dec=$(( 8#$perm ))
    if (( (mode_dec & 8#022) != 0 )); then
        warn "Lock directory candidate $candidate has unsafe group/world writable permissions: $perm"
        return 1
    fi

    return 0
}

get_installer_lock_path() {
    local uid="${EUID:-$(id -u)}"
    if installer_test_override_allowed && [[ -n "${OVERRIDE_EUID:-}" ]]; then
        uid="$OVERRIDE_EUID"
    fi

    if ! command_exists stat; then
        error "Required metadata utility 'stat' is missing; cannot establish lock directory safety."
        return 1
    fi

    # 1. Candidate: XDG_RUNTIME_DIR
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]] && validate_lock_directory "${XDG_RUNTIME_DIR}" "$uid"; then
        printf '%s/fedora-hyprland-workstation.lock\n' "${XDG_RUNTIME_DIR}"
        return 0
    fi

    # 2. Candidate: /run/user/$uid
    if validate_lock_directory "/run/user/${uid}" "$uid"; then
        printf '/run/user/%s/fedora-hyprland-workstation.lock\n' "$uid"
        return 0
    fi

    # 3. Candidate: private fallback in /tmp
    local fallback_dir="/tmp/.fhw-lock-${uid}"

    if [[ -L "$fallback_dir" ]]; then
        error "Refusing lock fallback directory that exists as a symlink: $fallback_dir"
        return 1
    fi

    if [[ ! -d "$fallback_dir" ]]; then
        if ! mkdir -m 0700 "$fallback_dir" 2>/dev/null; then
            error "Failed to create private lock directory: $fallback_dir"
            return 1
        fi
    fi

    if validate_lock_directory "$fallback_dir" "$uid"; then
        chmod 0700 "$fallback_dir" 2>/dev/null || true
        printf '%s/installer.lock\n' "$fallback_dir"
        return 0
    fi

    error "Could not establish a safe, verified lock directory for UID $uid."
    return 1
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

    if ! exec {INSTALLER_LOCK_FD}>"$INSTALLER_LOCK_FILE"; then
        die "Could not open installer lock file: $INSTALLER_LOCK_FILE"
    fi

    if ! flock -n "$INSTALLER_LOCK_FD"; then
        die "Another instance of the installer is currently running (locked at $INSTALLER_LOCK_FILE). Refusing concurrent execution."
    fi

    printf '%s\n' "$$" >&"$INSTALLER_LOCK_FD" 2>/dev/null || true
}

release_installer_lock() {
    if [[ -n "${INSTALLER_LOCK_FD:-}" ]]; then
        flock -u "$INSTALLER_LOCK_FD" 2>/dev/null || true
        exec {INSTALLER_LOCK_FD}>&- 2>/dev/null || true
        INSTALLER_LOCK_FD=""
    fi
}
