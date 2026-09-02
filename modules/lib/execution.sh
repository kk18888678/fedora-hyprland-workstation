#!/usr/bin/env bash

# Execution control, booleans, privilege transitions, timeouts, and retries.

is_true() {
    case "${1:-}" in
        true|TRUE|yes|YES|1)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_false() {
    case "${1:-}" in
        false|FALSE|no|NO|0)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

require_boolean() {
    local variable_name="$1"
    local value="${!variable_name:-}"

    if ! is_true "$value" && ! is_false "$value"; then
        die "$variable_name must be true or false. Current value: '${value:-<unset>}'"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    local command_name="$1"

    command_exists "$command_name" ||
        die "Required command not found: $command_name"
}

run_as_target_user() {
    local target_user="${TARGET_USER:-}"
    local target_home="${TARGET_HOME:-}"
    local effective_uid="${OVERRIDE_EUID:-$EUID}"

    [[ -n "$target_user" ]] || die "TARGET_USER is not defined."
    [[ -n "$target_home" ]] || die "TARGET_HOME is not defined."

    local target_uid=""
    if [[ -n "${OVERRIDE_TARGET_UID:-}" ]]; then
        target_uid="$OVERRIDE_TARGET_UID"
    elif command_exists id; then
        target_uid="$(id -u "$target_user" 2>/dev/null || true)"
    elif command_exists getent; then
        target_uid="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f3 || true)"
    fi

    # 1. If caller is already actually running as TARGET_USER (effective UID matches target UID)
    if [[ -n "$target_uid" ]] && (( effective_uid == target_uid )); then
        HOME="$target_home" USER="$target_user" "$@"
        return $?
    fi

    # If target_uid is unknown but effective user is not root and genuine login identity matches
    if [[ -z "$target_uid" && "$effective_uid" -ne 0 ]]; then
        local current_login=""
        if command_exists id; then
            current_login="$(id -un 2>/dev/null || true)"
        fi
        if [[ -n "$current_login" && "$current_login" == "$target_user" ]]; then
            HOME="$target_home" USER="$target_user" "$@"
            return $?
        fi
    fi

    # 2. If caller is root, perform genuine user switch via sudo
    if (( effective_uid == 0 )); then
        sudo -u "$target_user" env HOME="$target_home" USER="$target_user" "$@"
        return $?
    fi

    # 3. If caller is a different non-root user, perform privilege switch if sudo is available
    if command_exists sudo; then
        sudo -u "$target_user" env HOME="$target_home" USER="$target_user" "$@"
        return $?
    fi

    # 4. Fail closed: genuine user transition required but impossible
    error "Cannot execute command as target user '$target_user': process UID ($effective_uid) does not match target UID (${target_uid:-unknown}) and sudo is unavailable."
    return 1
}

TIMEOUT_METADATA_SECONDS=300       # 5 minutes: dnf makecache, repoquery, repo add
TIMEOUT_PACKAGE_SECONDS=900        # 15 minutes: dnf install transaction, copr enable
TIMEOUT_DOWNLOAD_SECONDS=300       # 5 minutes: direct curl/wget downloads
TIMEOUT_GIT_SECONDS=300            # 5 minutes: git clone / fetch
TIMEOUT_FLATPAK_SECONDS=600        # 10 minutes: Flatpak remote-add and package installs
TIMEOUT_NIX_SECONDS=600            # 10 minutes: Nix profile install and package evaluation

ACTIVE_TIMEOUT_PID=""

run_with_timeout() {
    local timeout_seconds="$1"
    local description="$2"
    shift 2

    if ! command_exists timeout; then
        error "Required safety utility 'timeout' is not available for: ${description}"
        return 127
    fi

    if (( timeout_seconds <= 0 )); then
        error "Invalid non-positive timeout (${timeout_seconds}s) for: ${description}"
        return 1
    fi

    local status=0
    timeout --kill-after=10s "${timeout_seconds}s" "$@" &
    ACTIVE_TIMEOUT_PID=$!
    wait "$ACTIVE_TIMEOUT_PID" || status=$?
    ACTIVE_TIMEOUT_PID=""

    if (( status == 124 || status == 137 )); then
        error "Operation timed out after ${timeout_seconds}s: ${description}"
        return 124
    fi

    return "$status"
}

# Override in tests: RETRY_BACKOFF_SECONDS=(0 0)
RETRY_BACKOFF_SECONDS=(2 5 10)

run_with_retry() {
    local description="$1"
    shift

    local delays=("${RETRY_BACKOFF_SECONDS[@]}")
    local max_attempts=$((${#delays[@]} + 1))
    local attempt=1
    local delay
    local status=0

    while true; do
        if "$@"; then
            return 0
        else
            status=$?
        fi

        if (( attempt >= max_attempts )); then
            error "Giving up after ${max_attempts} attempts: $description"
            return "$status"
        fi

        delay="${delays[$((attempt - 1))]}"
        warn "Attempt ${attempt}/${max_attempts} failed: ${description}. Retrying in ${delay}s."
        sleep "$delay"
        attempt=$((attempt + 1))
    done
}

SUDO_KEEPALIVE_PID=""

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

require_sudo() {
    info "Validating sudo access."

    sudo -v ||
        die "sudo authentication failed."

    (
        while true; do
            sleep 60
            sudo -n true || exit 1
        done
    ) >/dev/null 2>&1 &

    SUDO_KEEPALIVE_PID=$!
}

install_root_file_from_stdin() {
    local destination="$1"
    local mode="$2"
    local owner="$3"
    local group="$4"
    local temp_file

    temp_file="$(mktemp)"

    cat >"$temp_file"

    sudo install -D -m "$mode" -o "$owner" -g "$group" \
        "$temp_file" "$destination"

    rm -f "$temp_file"
}

install_root_file() {
    local source="$1"
    local destination="$2"
    local mode="$3"
    local owner="$4"
    local group="$5"

    [[ -f "$source" ]] ||
        die "Managed file is missing: $source"

    sudo install -D -m "$mode" -o "$owner" -g "$group" \
        "$source" "$destination"
}
