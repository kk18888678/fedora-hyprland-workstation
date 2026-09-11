#!/usr/bin/env bash

# Shared safety and validation primitives for workstation-packages.
#
# This file is sourced by the CLI backend. It deliberately contains no
# package-manager mutations and no repository writes.

wsp_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

wsp_warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

wsp_info() {
    printf '%s\n' "$*"
}

wsp_fail() {
    wsp_error "$*"
    return 1
}

wsp_require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 ||
        wsp_fail "Required command is unavailable: $command_name"
}

wsp_valid_provider() {
    [[ "${1:-}" == "dnf" || "${1:-}" == "flatpak" || "${1:-}" == "aurelia" ]]
}

wsp_valid_source() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,127}$ ]]
}

wsp_valid_dnf_id() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9+._:-]{0,127}$ ]]
}

wsp_dnf_native_arch() {
    case "$(uname -m)" in
        x86_64) printf '%s\n' x86_64 ;;
        aarch64|arm64) printf '%s\n' aarch64 ;;
        *) return 1 ;;
    esac
}

wsp_dnf_install_identifier() {
    local identifier="$1"
    local arch

    arch="$(wsp_dnf_native_arch)" || return 1
    if [[ "$identifier" == *."$arch" || "$identifier" == *.noarch ]]; then
        printf '%s\n' "$identifier"
    else
        printf '%s.%s\n' "$identifier" "$arch"
    fi
}

wsp_valid_flatpak_id() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]
}

wsp_valid_scope() {
    [[ "${1:-}" == "system" || "${1:-}" == "user" ]]
}

wsp_path_components_safe() {
    local path="${1:-}"
    local current="/"
    local component
    local components=()
    local IFS='/'

    [[ "$path" == /* && "$path" != "/" ]] || return 1
    read -r -a components <<< "${path#/}"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        [[ "$component" != "." && "$component" != ".." ]] || return 1
        current="${current%/}/$component"
        [[ ! -L "$current" ]] || return 1
    done
}

wsp_valid_profiles() {
    case "${1:-}" in
        all|workstation|vm|"workstation vm"|"vm workstation") return 0 ;;
        *) return 1 ;;
    esac
}

wsp_validate_record() {
    local provider="$1"
    local source="$2"
    local identifier="$3"
    local scope="$4"
    local profiles="$5"

    wsp_valid_provider "$provider" || return 1
    wsp_valid_source "$source" || return 1
    case "$provider" in
        dnf)
            wsp_valid_dnf_id "$identifier" || return 1
            ;;
        flatpak)
            wsp_valid_flatpak_id "$identifier" || return 1
            ;;
        aurelia)
            wsp_valid_dnf_id "$identifier" || return 1
            [[ "$scope" == user ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac
    wsp_valid_scope "$scope" || return 1
    wsp_valid_profiles "$profiles" || return 1
}

wsp_validate_url() {
    local url="$1"
    [[ "$url" =~ ^https://[^[:space:]]+$ ]]
}

wsp_run_timeout() {
    local seconds="$1"
    shift

    [[ "$seconds" =~ ^[0-9]+$ && "$seconds" -gt 0 ]] || {
        wsp_error "Invalid timeout: $seconds"
        return 2
    }
    command -v timeout >/dev/null 2>&1 || {
        wsp_error "timeout is required; refusing an unbounded package operation."
        return 127
    }

    timeout --foreground --kill-after=5s "${seconds}s" "$@"
}

wsp_repo_root_is_safe() {
    local root="$1"
    [[ -n "$root" && "$root" == /* && "$root" != "/" ]] || return 1
    wsp_path_components_safe "$root" || return 1
    [[ -d "$root" && ! -L "$root" ]] || return 1
    [[ -d "$root/packages" && ! -L "$root/packages" ]] || return 1
    return 0
}

wsp_target_is_safe() {
    local target="$1"
    local parent

    [[ -n "$target" && "$target" == /* && "$target" != "/" ]] || return 1
    wsp_path_components_safe "$target" || return 1
    [[ ! -L "$target" ]] || return 1
    [[ ! -e "$target" || -f "$target" ]] || return 1
    [[ ! -e "$target" || -f "$target" ]] || return 1
    parent="$(dirname -- "$target")"
    [[ -d "$parent" && ! -L "$parent" ]] || return 1
    return 0
}

wsp_atomic_replace() {
    local target="$1"
    local source_file="$2"
    local target_dir
    local target_name
    local temporary

    [[ -f "$source_file" ]] || {
        wsp_error "Atomic replacement source is missing: $source_file"
        return 1
    }
    wsp_target_is_safe "$target" || {
        wsp_error "Refusing unsafe package-manager target: $target"
        return 1
    }

    target_dir="$(dirname -- "$target")"
    target_name="$(basename -- "$target")"
    temporary="$(mktemp "$target_dir/.${target_name}.XXXXXX")" || {
        wsp_error "Could not create an atomic staging file beside: $target"
        return 1
    }

    if ! cp -- "$source_file" "$temporary"; then
        rm -f -- "$temporary"
        wsp_error "Could not stage atomic replacement for: $target"
        return 1
    fi
    chmod 0644 -- "$temporary" || {
        rm -f -- "$temporary"
        wsp_error "Could not set package manifest permissions: $target"
        return 1
    }
    if ! mv -T -- "$temporary" "$target"; then
        rm -f -- "$temporary"
        wsp_error "Could not publish package manifest: $target"
        return 1
    fi
}

wsp_runtime_directory() {
    local uid
    local candidate
    local fallback_base

    uid="$(id -u)" || return 1
    for candidate in "${XDG_RUNTIME_DIR:-}" "/run/user/$uid"; do
        [[ -n "$candidate" ]] || continue
        [[ "$candidate" == /* && "$candidate" != "/" ]] || continue
        [[ -d "$candidate" && ! -L "$candidate" && -O "$candidate" && -w "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    # Some development sandboxes expose /run/user/$UID as read-only. Keep the
    # package operation lock fail-closed and recoverable by using a private,
    # user-owned fallback rather than silently running unlocked.
    for fallback_base in \
        "${XDG_STATE_HOME:-$HOME/.local/state}/fedora-hyprland-workstation" \
        "/tmp/.fhw-package-runtime-$uid"; do
        [[ "$fallback_base" == /* && "$fallback_base" != "/" ]] || continue
        if [[ -L "$fallback_base" ]]; then
            continue
        fi
        if [[ ! -d "$fallback_base" ]]; then
            mkdir -m 0700 -- "$fallback_base" 2>/dev/null || continue
        fi
        chmod 0700 -- "$fallback_base" 2>/dev/null || continue
        [[ -O "$fallback_base" && -w "$fallback_base" ]] || continue
        printf '%s\n' "$fallback_base"
        return 0
    done
    return 1
}

wsp_lock_start() {
    local runtime_dir
    local lock_path

    command -v flock >/dev/null 2>&1 || {
        wsp_error "flock is required; refusing concurrent package operations."
        return 1
    }
    runtime_dir="$(wsp_runtime_directory)" || {
        wsp_error "A safe per-user runtime directory is unavailable; refusing package operations."
        return 1
    }
    lock_path="$runtime_dir/fedora-hyprland-workstation-packages.lock"
    [[ ! -L "$lock_path" ]] || {
        wsp_error "Package operation lock path is a symlink: $lock_path"
        return 1
    }
    exec {WSP_LOCK_FD}>"$lock_path" || {
        wsp_error "Could not open the package operation lock: $lock_path"
        return 1
    }
    if ! flock -n "$WSP_LOCK_FD"; then
        exec {WSP_LOCK_FD}>&-
        WSP_LOCK_FD=""
        wsp_error "Another workstation package operation is already running."
        return 1
    fi
    WSP_LOCK_PATH="$lock_path"
}

wsp_lock_stop() {
    if [[ -n "${WSP_LOCK_FD:-}" ]]; then
        flock -u "$WSP_LOCK_FD" 2>/dev/null || true
        exec {WSP_LOCK_FD}>&- 2>/dev/null || true
        WSP_LOCK_FD=""
    fi
}

wsp_trim_line() {
    local value="$1"
    value="${value%$'\r'}"
    printf '%s' "$value"
}
