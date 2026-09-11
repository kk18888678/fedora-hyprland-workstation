#!/usr/bin/env bash

# Container tooling for Fedora Hyprland Workstation.
#
# Fedora owns the host container runtime.
# Project-specific container definitions remain inside each project.
#
# Default stack:
#   Podman
#   Buildah
#   Skopeo
#   podman-compose
#
# Containers are intended to run rootless for the target user.

install_container_packages() {
    local packages=(
        podman
        buildah
        skopeo
        podman-compose
    )

    info "Installing container tooling."

    install_dnf_packages "${packages[@]}"
}

detect_container_package_group() {
    local package
    for package in podman buildah skopeo podman-compose; do
        package_installed "$package" || return 1
    done
}

install_container_package_group() {
    install_container_packages
}

ROOTLESS_SUBID_RANGE_SIZE=65536
ROOTLESS_SUBID_FIRST_START=100000
ROOTLESS_SUBID_MAX_ATTEMPTS=4096

subid_file_path() {
    case "${1:-}" in
        uid)
            if installer_test_override_allowed && [[ -n "${SUBUID_FILE:-}" ]]; then
                printf '%s\n' "$SUBUID_FILE"
            else
                printf '%s\n' /etc/subuid
            fi
            ;;
        gid)
            if installer_test_override_allowed && [[ -n "${SUBGID_FILE:-}" ]]; then
                printf '%s\n' "$SUBGID_FILE"
            else
                printf '%s\n' /etc/subgid
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

validate_subid_file() {
    local file="$1"

    # shadow-utils may create a missing file when usermod adds the first
    # range.  Treat that case as an empty, valid allocation table.
    [[ ! -e "$file" ]] && return 0
    [[ -f "$file" && ! -L "$file" && -r "$file" ]] || return 1

    awk -F: '
        /^[[:space:]]*#/ || NF == 0 { next }
        NF != 3 || $1 !~ /^[^:[:space:]]+$/ ||
            $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ || $3 == 0 {
            invalid = 1
        }
        END { exit invalid ? 1 : 0 }
    ' "$file"
}

subid_user_range() {
    local file="$1"
    local user="$2"

    validate_subid_file "$file" || return 1
    [[ -f "$file" ]] || return 1

    awk -F: -v wanted_user="$user" '
        $1 == wanted_user {
            print $2 ":" $3
            found = 1
            exit
        }
        END { exit found ? 0 : 1 }
    ' "$file"
}

subid_range_is_free() {
    local file="$1"
    local start="$2"
    local count="$3"

    [[ "$start" =~ ^[0-9]+$ && "$count" =~ ^[1-9][0-9]*$ ]] || return 1
    validate_subid_file "$file" || return 1
    [[ -f "$file" ]] || return 0

    awk -F: -v candidate_start="$start" -v candidate_count="$count" '
        /^[[:space:]]*#/ || NF == 0 { next }
        {
            existing_start = $2
            existing_end = $2 + $3
            candidate_end = candidate_start + candidate_count
            if (candidate_start < existing_end && candidate_end > existing_start) {
                overlap = 1
            }
        }
        END { exit overlap ? 1 : 0 }
    ' "$file"
}

find_free_subid_range() {
    local uid_file="$1"
    local gid_file="$2"
    local start="$ROOTLESS_SUBID_FIRST_START"
    local attempt

    for (( attempt = 0; attempt < ROOTLESS_SUBID_MAX_ATTEMPTS; attempt++ )); do
        if subid_range_is_free "$uid_file" "$start" "$ROOTLESS_SUBID_RANGE_SIZE" &&
            subid_range_is_free "$gid_file" "$start" "$ROOTLESS_SUBID_RANGE_SIZE"; then
            printf '%s-%s\n' "$start" "$((start + ROOTLESS_SUBID_RANGE_SIZE - 1))"
            return 0
        fi
        start=$((start + ROOTLESS_SUBID_RANGE_SIZE))
    done

    return 1
}

subid_range_has_required_size() {
    local range="$1"
    local start
    local count

    [[ "$range" =~ ^([0-9]+):([0-9]+)$ ]] || return 1
    start="${BASH_REMATCH[1]}"
    count="${BASH_REMATCH[2]}"
    [[ "$start" =~ ^[0-9]+$ && "$count" =~ ^[0-9]+$ ]] || return 1
    (( count >= ROOTLESS_SUBID_RANGE_SIZE ))
}

subid_range_start() {
    local range="$1"
    [[ "$range" =~ ^([0-9]+):([0-9]+)$ ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}

ensure_rootless_subids() {
    local uid_file
    local gid_file
    uid_file="$(subid_file_path uid)" || return 1
    gid_file="$(subid_file_path gid)" || return 1

    validate_subid_file "$uid_file" || return 1
    validate_subid_file "$gid_file" || return 1

    local uid_range=""
    local gid_range=""
    uid_range="$(subid_user_range "$uid_file" "$TARGET_USER" 2>/dev/null || true)"
    gid_range="$(subid_user_range "$gid_file" "$TARGET_USER" 2>/dev/null || true)"

    if [[ -n "$uid_range" && -n "$gid_range" ]]; then
        return 0
    fi

    local selected_range=""
    local existing_range=""
    if [[ -n "$uid_range" && -z "$gid_range" ]] &&
        subid_range_has_required_size "$uid_range"; then
        existing_range="$uid_range"
        if subid_range_is_free "$gid_file" \
            "$(subid_range_start "$existing_range")" \
            "$ROOTLESS_SUBID_RANGE_SIZE"; then
            selected_range="$(subid_range_start "$existing_range")-$(($(subid_range_start "$existing_range") + ROOTLESS_SUBID_RANGE_SIZE - 1))"
        fi
    elif [[ -n "$gid_range" && -z "$uid_range" ]] &&
        subid_range_has_required_size "$gid_range"; then
        existing_range="$gid_range"
        if subid_range_is_free "$uid_file" \
            "$(subid_range_start "$existing_range")" \
            "$ROOTLESS_SUBID_RANGE_SIZE"; then
            selected_range="$(subid_range_start "$existing_range")-$(($(subid_range_start "$existing_range") + ROOTLESS_SUBID_RANGE_SIZE - 1))"
        fi
    fi

    if [[ -z "$selected_range" ]]; then
        selected_range="$(find_free_subid_range "$uid_file" "$gid_file")" || return 1
    fi

    if [[ -z "$uid_range" ]]; then
        info "Adding subordinate UID range for $TARGET_USER: $selected_range."
        sudo usermod --add-subuids "$selected_range" "$TARGET_USER" ||
            return 1
    fi

    if [[ -z "$gid_range" ]]; then
        info "Adding subordinate GID range for $TARGET_USER: $selected_range."
        sudo usermod --add-subgids "$selected_range" "$TARGET_USER" ||
            return 1
    fi

    [[ -n "$(subid_user_range "$uid_file" "$TARGET_USER" 2>/dev/null || true)" &&
       -n "$(subid_user_range "$gid_file" "$TARGET_USER" 2>/dev/null || true)" ]]
}

configure_rootless_storage() {
    local containers_dir="$TARGET_HOME/.config/containers"

    safe_user_config_home "$containers_dir" || return 1
    ensure_directory "$containers_dir" || return 1

    info "Rootless container configuration directory ready."
}

enable_podman_socket() {
    if systemctl --user list-unit-files podman.socket \
        --no-legend 2>/dev/null | grep '^podman.socket' >/dev/null 2>&1; then

        info "Enabling Podman user socket."

        if ! systemctl --user enable podman.socket; then
            record_deferred \
                "containers" \
                "podman.socket" \
                "Could not enable the Podman user socket in this session."
            return 0
        fi

        # Starting the socket can fail over SSH without a lingering user
        # manager. Enable-for-next-session is enough; do not fail the host.
        if ! systemctl --user start podman.socket; then
            record_deferred \
                "containers" \
                "podman.socket" \
                "Podman user socket could not be started in the current session."
        fi
    else
        record_deferred \
            "containers" \
            "podman.socket" \
            "podman.socket user unit was not found."
    fi
}

configure_containers() {
    if ! is_true "${PODMAN:-false}"; then
        info "Podman disabled by profile."
        return 0
    fi

    info "Configuring container environment."

    if is_component_migrated "packages.containers"; then
        info "Container package group is owned by configuration reconciler; skipping legacy stage."
    elif ! install_container_packages; then
        record_required "containers" "packages" "Container packages could not be installed."
        return 1
    fi

    local command_name
    for command_name in podman buildah skopeo podman-compose; do
        if ! command_exists "$command_name"; then
            record_required "containers" "$command_name" "Required container command is missing."
            return 1
        fi
    done

    if ! ensure_rootless_subids; then
        record_required "containers" "subids" "Could not ensure /etc/subuid and /etc/subgid ranges."
        return 1
    fi

    if ! configure_rootless_storage; then
        record_required \
            "containers" \
            "storage" \
            "Rootless container configuration directory is unsafe or unavailable."
        return 1
    fi
    enable_podman_socket

    if ! podman info >/dev/null 2>&1; then
        record_required "containers" "podman info" "Rootless Podman validation failed."
        return 1
    fi

    info "Container environment configured."
    record_success "containers"
    return 0
}
