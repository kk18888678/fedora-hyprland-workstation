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

validate_container_commands() {
    local commands=(
        podman
        buildah
        skopeo
        podman-compose
    )

    local command_name

    for command_name in "${commands[@]}"; do
        command_exists "$command_name" ||
            die "Required container command not found: $command_name"
    done

    info "Container commands validated."
}

validate_rootless_subids() {
    local subuid_entry
    local subgid_entry

    subuid_entry="$(grep -E "^${TARGET_USER}:" /etc/subuid || true)"
    subgid_entry="$(grep -E "^${TARGET_USER}:" /etc/subgid || true)"

    if [[ -z "$subuid_entry" ]]; then
        die "No subordinate UID range found for $TARGET_USER in /etc/subuid."
    fi

    if [[ -z "$subgid_entry" ]]; then
        die "No subordinate GID range found for $TARGET_USER in /etc/subgid."
    fi

    info "Rootless subordinate UID/GID ranges validated."
}

configure_rootless_storage() {
    local containers_dir="$TARGET_HOME/.config/containers"

    ensure_directory "$containers_dir"

    info "Rootless container configuration directory ready."
}

enable_podman_socket() {
    if systemctl --user list-unit-files podman.socket \
        --no-legend 2>/dev/null | grep -q '^podman.socket'; then

        info "Enabling Podman user socket."

        systemctl --user enable --now podman.socket ||
            warn "Could not start the Podman user socket in the current session."
    else
        warn "podman.socket user unit was not found."
    fi
}

validate_podman() {
    info "Validating Podman."

    podman info >/dev/null ||
        die "Podman rootless validation failed."

    info "Podman validated."
}

configure_containers() {
    if ! is_true "${PODMAN:-false}"; then
        info "Podman disabled by profile."
        return 0
    fi

    info "Configuring container environment."

    install_container_packages
    validate_container_commands
    validate_rootless_subids
    configure_rootless_storage
    enable_podman_socket
    validate_podman

    info "Container environment configured."
}
