#!/usr/bin/env bash
# User-facing Aurelia Shell plugin lifecycle commands.

print_aurelia_plugin_help() {
    cat <<'USAGE'
Usage: aurelia-plugin <command> [arguments]

Commands:
  validate [--first-party] <directory>
  list
  rescan
  enable <plugin-id>
  disable <plugin-id>
  add <https-git-url> [--enable] --yes
  update <plugin-id> --yes
  remove <plugin-id> --yes

Third-party plugins are user-owned, unsandboxed QML code. Review a plugin
before enabling it. The CLI never runs plugin install hooks.
USAGE
}

aurelia_plugin_wait_for_scan() {
    local shell_cli="$1"
    local plugin_id="$2"
    local listing
    for _ in {1..20}; do
        listing="$("$shell_cli" shell listPlugins 2>/dev/null || true)"
        if jq -e --arg id "$plugin_id" '.[] | select(.id == $id)' <<< "$listing" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

aurelia_plugin_reload_shell() {
    local shell_cli
    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    "$shell_cli" shell rescanPlugins >/dev/null
}

aurelia_plugin_set_enabled() {
    local plugin_id="$1"
    local enabled="$2"
    aurelia_plugin_require_id "$plugin_id" || return 1
    local shell_cli
    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    aurelia_plugin_wait_for_scan "$shell_cli" "$plugin_id" || {
        aurelia_plugin_fail "Plugin is not present in the resident registry: $plugin_id"
        return 1
    }
    "$shell_cli" shell setPluginEnabled "$plugin_id" "$enabled"
}

aurelia_plugin_clone_remote() {
    local remote_url="$1"
    local destination="$2"
    [[ "$remote_url" =~ ^https://[^[:space:]]+$ ]] || {
        aurelia_plugin_fail "Only HTTPS git URLs are accepted"
        return 1
    }
    local timeout_bin
    timeout_bin="$(aurelia_plugin_require_timeout)" || return 1
    GIT_TERMINAL_PROMPT=0 "$timeout_bin" --kill-after=5s 60s git clone --depth 1 --no-tags -- "$remote_url" "$destination"
}

aurelia_plugin_add() {
    local remote_url="$1"
    shift
    local enable=0 yes=0 arg
    for arg in "$@"; do
        case "$arg" in
            --enable) enable=1 ;;
            --yes) yes=1 ;;
            *) aurelia_plugin_fail "Unknown add option: $arg"; return 1 ;;
        esac
    done
    [[ "$yes" -eq 1 ]] || aurelia_plugin_fail "add requires --yes because it downloads and installs unsandboxed code"
    aurelia_plugin_require_root || return 1

    local staging plugin_path plugin_id target
    staging="$(mktemp -d "$aurelia_plugin_dir/.add.XXXXXX")" || return 1
    AURELIA_PLUGIN_STAGING="$staging"
    trap 'if [[ -n "${AURELIA_PLUGIN_STAGING:-}" && "${AURELIA_PLUGIN_STAGING}" == "${aurelia_plugin_dir}"/.add.* ]]; then rm -rf -- "${AURELIA_PLUGIN_STAGING}"; fi' EXIT
    plugin_path="$staging/source"
    aurelia_plugin_clone_remote "$remote_url" "$plugin_path" || return 1
    aurelia_plugin_validate_manifest "$plugin_path" 0 0 || return 1
    plugin_id="$(aurelia_plugin_manifest_id "$plugin_path")"
    target="$(aurelia_plugin_target "$plugin_id")" || return 1
    [[ ! -e "$target" && ! -L "$target" ]] || {
        aurelia_plugin_fail "Plugin target already exists: $target"
        return 1
    }
    mv -- "$plugin_path" "$target"
    AURELIA_PLUGIN_STAGING=""
    rm -rf -- "$staging"

    aurelia_plugin_reload_shell || {
        aurelia_plugin_fail "Plugin installed but the resident shell could not rescan it"
        return 1
    }
    if [[ "$enable" -eq 1 ]]; then
        aurelia_plugin_set_enabled "$plugin_id" true || return 1
    fi
    printf 'Installed %s (disabled until reviewed%s).\n' "$plugin_id" "$([[ "$enable" -eq 1 ]] && echo ' and explicitly enabled' || true)"
}

aurelia_plugin_update() {
    local plugin_id="$1"
    shift
    local yes=0 arg
    for arg in "$@"; do
        [[ "$arg" == "--yes" ]] || { aurelia_plugin_fail "Unknown update option: $arg"; return 1; }
        yes=1
    done
    [[ "$yes" -eq 1 ]] || aurelia_plugin_fail "update requires --yes"
    aurelia_plugin_require_root || return 1
    local target remote staging new_plugin backup
    target="$(aurelia_plugin_target "$plugin_id")" || return 1
    [[ -d "$target" && ! -L "$target" && -d "$target/.git" ]] || {
        aurelia_plugin_fail "Plugin is not a git-managed checkout: $plugin_id"
        return 1
    }
    [[ -z "$(git -C "$target" status --porcelain 2>/dev/null)" ]] || {
        aurelia_plugin_fail "Plugin has local changes; refusing an in-place update: $plugin_id"
        return 1
    }
    remote="$(git -C "$target" config --get remote.origin.url 2>/dev/null || true)"
    [[ "$remote" =~ ^https://[^[:space:]]+$ ]] || {
        aurelia_plugin_fail "Plugin remote is not an HTTPS URL: $plugin_id"
        return 1
    }
    staging="$(mktemp -d "$aurelia_plugin_dir/.update.XXXXXX")" || return 1
    AURELIA_PLUGIN_STAGING="$staging"
    trap 'if [[ -n "${AURELIA_PLUGIN_STAGING:-}" && "${AURELIA_PLUGIN_STAGING}" == "${aurelia_plugin_dir}"/.update.* ]]; then rm -rf -- "${AURELIA_PLUGIN_STAGING}"; fi' EXIT
    new_plugin="$staging/source"
    aurelia_plugin_clone_remote "$remote" "$new_plugin" || return 1
    aurelia_plugin_validate_manifest "$new_plugin" 0 0 || return 1
    [[ "$(aurelia_plugin_manifest_id "$new_plugin")" == "$plugin_id" ]] || {
        aurelia_plugin_fail "Updated repository changed its plugin id"
        return 1
    }
    local backup_dir
    backup_dir="$(mktemp -d "$aurelia_plugin_dir/.update-backup.XXXXXX")" || return 1
    backup="$backup_dir/old"
    mv -- "$target" "$backup" || { rm -rf -- "$backup_dir"; return 1; }
    if ! mv -- "$new_plugin" "$target"; then
        mv -- "$backup" "$target"
        rm -rf -- "$backup_dir"
        return 1
    fi
    rm -rf -- "$backup_dir"
    AURELIA_PLUGIN_STAGING=""
    rm -rf -- "$staging"
    aurelia_plugin_reload_shell || {
        aurelia_plugin_fail "Plugin updated but the resident shell could not rescan it"
        return 1
    }
    printf 'Updated %s.\n' "$plugin_id"
}

aurelia_plugin_remove() {
    local plugin_id="$1"
    shift
    local yes=0 arg
    for arg in "$@"; do
        [[ "$arg" == "--yes" ]] || { aurelia_plugin_fail "Unknown remove option: $arg"; return 1; }
        yes=1
    done
    [[ "$yes" -eq 1 ]] || aurelia_plugin_fail "remove requires --yes"
    aurelia_plugin_require_root || return 1
    local target
    target="$(aurelia_plugin_target "$plugin_id")" || return 1
    [[ -d "$target" && ! -L "$target" ]] || {
        aurelia_plugin_fail "Plugin directory does not exist: $plugin_id"
        return 1
    }
    aurelia_plugin_validate_manifest "$target" 0 || return 1
    [[ "$(aurelia_plugin_manifest_id "$target")" == "$plugin_id" ]] || return 1
    rm -rf -- "$target"
    aurelia_plugin_reload_shell || {
        aurelia_plugin_fail "Plugin removed but the resident shell could not rescan it"
        return 1
    }
    printf 'Removed %s.\n' "$plugin_id"
}

aurelia_plugin_main() {
    local command="${1:-help}"
    shift || true
    case "$command" in
        help|-h|--help)
            print_aurelia_plugin_help
            ;;
        validate)
            local allow_first_party=0
            if [[ "${1:-}" == "--first-party" ]]; then allow_first_party=1; shift; fi
            [[ $# -eq 1 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin validate [--first-party] <directory>"; return 1; }
            aurelia_plugin_validate_manifest "$1" "$allow_first_party" || return 1
            printf 'Valid Aurelia plugin: %s\n' "$(aurelia_plugin_manifest_id "$1")"
            ;;
        list)
            [[ $# -eq 0 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin list"; return 1; }
            local shell_cli
            shell_cli="$(aurelia_plugin_shell_cli)" || return 1
            "$shell_cli" shell listPlugins
            ;;
        rescan)
            [[ $# -eq 0 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin rescan"; return 1; }
            aurelia_plugin_reload_shell
            ;;
        enable|disable)
            [[ $# -eq 1 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin $command <plugin-id>"; return 1; }
            aurelia_plugin_set_enabled "$1" "$([[ "$command" == enable ]] && echo true || echo false)"
            ;;
        add)
            [[ $# -ge 1 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin add <https-git-url> [--enable] --yes"; return 1; }
            local url="$1"
            shift
            aurelia_plugin_add "$url" "$@"
            ;;
        update)
            [[ $# -ge 1 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin update <plugin-id> --yes"; return 1; }
            local update_id="$1"
            shift
            aurelia_plugin_update "$update_id" "$@"
            ;;
        remove)
            [[ $# -ge 1 ]] || { aurelia_plugin_fail "Usage: aurelia-plugin remove <plugin-id> --yes"; return 1; }
            local remove_id="$1"
            shift
            aurelia_plugin_remove "$remove_id" "$@"
            ;;
        *)
            aurelia_plugin_fail "Unknown command: $command"
            print_aurelia_plugin_help >&2
            return 1
            ;;
    esac
}
