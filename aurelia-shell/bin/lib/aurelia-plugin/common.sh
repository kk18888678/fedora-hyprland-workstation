#!/usr/bin/env bash
# Shared paths and validation primitives for aurelia-plugin.

[[ "${AURELIA_PLUGIN_COMMON_LOADED:-0}" == "1" ]] && return 0
AURELIA_PLUGIN_COMMON_LOADED=1

aurelia_plugin_home="${HOME:-}"
aurelia_plugin_config_home="${XDG_CONFIG_HOME:-$aurelia_plugin_home/.config}"
if [[ "$aurelia_plugin_config_home" != /* ]]; then
    aurelia_plugin_config_home="$aurelia_plugin_home/.config"
fi
aurelia_plugin_dir="${AURELIA_PLUGIN_DIR:-$aurelia_plugin_config_home/aurelia/plugins}"

aurelia_plugin_fail() {
    printf 'Error: %s\n' "$1" >&2
    return 1
}

aurelia_plugin_valid_id() {
    [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ && "${1:-}" != *..* ]]
}

aurelia_plugin_require_id() {
    local id="$1"
    aurelia_plugin_valid_id "$id" || aurelia_plugin_fail "Invalid plugin id: $id"
}

aurelia_plugin_shell_cli() {
    if [[ "${AURELIA_DEVELOPMENT_MODE:-0}" == "1" && -x "${AURELIA_PLUGIN_BIN_DIR:-$script_dir}/aurelia-shell" ]]; then
        printf '%s\n' "${AURELIA_PLUGIN_BIN_DIR:-$script_dir}/aurelia-shell"
    elif [[ -x "/usr/local/bin/aurelia-shell" ]]; then
        printf '%s\n' "/usr/local/bin/aurelia-shell"
    else
        aurelia_plugin_fail "aurelia-shell IPC client is not installed"
    fi
}

aurelia_plugin_require_timeout() {
    if [[ -x "/usr/bin/timeout" ]]; then
        printf '%s\n' "/usr/bin/timeout"
    else
        aurelia_plugin_fail "Required safety utility 'timeout' is not available"
    fi
}

aurelia_plugin_require_root() {
    [[ "$aurelia_plugin_dir" == /* && "$aurelia_plugin_dir" != "/" ]] ||
        aurelia_plugin_fail "Plugin directory must be an absolute non-root path"
    if [[ -L "$aurelia_plugin_dir" ]]; then
        aurelia_plugin_fail "Refusing symlinked plugin directory: $aurelia_plugin_dir"
        return 1
    fi
    mkdir -p "$aurelia_plugin_dir"
}

aurelia_plugin_target() {
    local id="$1"
    aurelia_plugin_require_id "$id" || return 1
    printf '%s/%s\n' "$aurelia_plugin_dir" "$id"
}
