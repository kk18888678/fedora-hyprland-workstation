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

ensure_rootless_subids() {
    if ! grep -qE "^${TARGET_USER}:" /etc/subuid; then
        info "Adding subordinate UID range for $TARGET_USER."
        sudo usermod --add-subuids 100000-165535 "$TARGET_USER" ||
            return 1
    fi

    if ! grep -qE "^${TARGET_USER}:" /etc/subgid; then
        info "Adding subordinate GID range for $TARGET_USER."
        sudo usermod --add-subgids 100000-165535 "$TARGET_USER" ||
            return 1
    fi

    grep -qE "^${TARGET_USER}:" /etc/subuid &&
        grep -qE "^${TARGET_USER}:" /etc/subgid
}

configure_rootless_storage() {
    local containers_dir="$TARGET_HOME/.config/containers"

    ensure_directory "$containers_dir"

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

    if ! install_container_packages; then
        record_required "containers" "packages" "Container packages could not be installed."
        return 0
    fi

    local command_name
    for command_name in podman buildah skopeo podman-compose; do
        if ! command_exists "$command_name"; then
            record_required "containers" "$command_name" "Required container command is missing."
            return 0
        fi
    done

    if ! ensure_rootless_subids; then
        record_required "containers" "subids" "Could not ensure /etc/subuid and /etc/subgid ranges."
        return 0
    fi

    configure_rootless_storage
    enable_podman_socket

    if ! podman info >/dev/null 2>&1; then
        record_required "containers" "podman info" "Rootless Podman validation failed."
        return 0
    fi

    info "Container environment configured."
    record_success "containers"
}
