#!/usr/bin/env bash
# Shared, side-effect-bounded setup for Aurelia Keybindings commands.
#
# This file owns only process setup, manifest resolution, logging, and the
# fixed production paths shared by the query, mutation, and runtime modules.
# It deliberately does not implement a user-facing command.

[[ "${AURELIA_KEYBINDINGS_COMMON_LOADED:-0}" == "1" ]] && return 0
AURELIA_KEYBINDINGS_COMMON_LOADED=1

: "${AURELIA_KEYBINDINGS_BIN_DIR:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
readonly AURELIA_KEYBINDINGS_BIN_DIR
: "${AURELIA_KEYBINDINGS_LIB_DIR:=$AURELIA_KEYBINDINGS_BIN_DIR/lib/aurelia-keybindings}"
readonly AURELIA_KEYBINDINGS_LIB_DIR

script_dir="$AURELIA_KEYBINDINGS_BIN_DIR"

aurelia_keybindings_dev_or_test() {
    [[ "${AURELIA_DEVELOPMENT_MODE:-0}" == "1" || "${WORKSTATION_TEST_MODE:-0}" == "1" ]]
}

# A development/test override is intentionally exported only in isolated
# modes. Production callers use the installed fixed path.
if aurelia_keybindings_dev_or_test; then
    export AURELIA_SHELL_KEYBINDINGS_BIN="${AURELIA_SHELL_KEYBINDINGS_BIN:-$script_dir/aurelia-shell-keybindings}"
fi

if [[ "${WORKSTATION_TEST_MODE:-0}" == "1" && -z "${XDG_STATE_HOME:-}" ]]; then
    LOG_DIR="/tmp/workstation-tests-${UID:-1000}"
else
    LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workstation"
fi
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
KEYBINDINGS_LOG="$LOG_DIR/keybindings.log"
CRASH_LOG="$LOG_DIR/crashes.log"
AURELIA_LOG="$LOG_DIR/aurelia.log"
PERF_LOG="$LOG_DIR/performance.log"

bound_logfile() {
    local logfile="$1"
    local max_lines=2000
    if [[ -f "$logfile" ]]; then
        local line_count
        line_count="$(wc -l < "$logfile" 2>/dev/null || echo 0)"
        if [[ "$line_count" -gt "$max_lines" ]]; then
            local tmp_log
            tmp_log="$(mktemp "${logfile}.tmp.XXXXXX" 2>/dev/null || true)"
            if [[ -n "$tmp_log" ]]; then
                tail -n 2000 "$logfile" > "$tmp_log" 2>/dev/null || true
                mv -f "$tmp_log" "$logfile" 2>/dev/null || rm -f "$tmp_log"
            fi
        fi
    fi
}

log_event() {
    local level="$1"
    local message="$2"
    local operation="${3:-core}"
    local duration="${4:-0}"
    local timestamp
    timestamp="$(date -Iseconds 2>/dev/null || date)"

    logger -t aurelia-shell-keybindings "[$level] [$operation] $message" 2>/dev/null || true
    if [[ -d "$LOG_DIR" ]]; then
        printf '%s [%s] [%s] %s\n' "$timestamp" "$level" "$operation" "$message" >> "$KEYBINDINGS_LOG" 2>/dev/null || true
        bound_logfile "$KEYBINDINGS_LOG"
        if [[ "$level" == "CRASH" || "$level" == "FATAL" || "$level" == "ERROR" ]]; then
            printf '%s [%s] [%s] %s\n' "$timestamp" "$level" "$operation" "$message" >> "$CRASH_LOG" 2>/dev/null || true
            bound_logfile "$CRASH_LOG"
        fi
        if [[ "$level" == "PERF" || "$level" == "PERF-WARN" ]]; then
            printf '%s [%s] [%s] %s (dur=%sms)\n' "$timestamp" "$level" "$operation" "$message" "$duration" >> "$PERF_LOG" 2>/dev/null || true
            bound_logfile "$PERF_LOG"
        fi
    fi
}

notify_user() {
    local urgency="$1"
    local title="$2"
    local message="$3"
    if [[ "${WORKSTATION_TEST_MODE:-0}" == "1" || -n "${HOTKEYS_TEST_PROVIDER:-}" ||
          -n "${HOTKEYS_SIMULATE_AURELIA_FAIL:-}" || -n "${AURELIA_TEST_MODE:-}" ]]; then
        return 0
    fi
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
    fi
}

manifest_path=""
if [[ -n "${KEYBINDINGS_MANIFEST:-}" && -f "$KEYBINDINGS_MANIFEST" ]]; then
    manifest_path="$KEYBINDINGS_MANIFEST"
elif [[ -n "${HOTKEYS_MANIFEST:-}" && -f "$HOTKEYS_MANIFEST" ]]; then
    manifest_path="$HOTKEYS_MANIFEST"
elif [[ -f "${HOME:-}/.config/hypr/keybindings_manifest.lua" ]]; then
    manifest_path="${HOME:-}/.config/hypr/keybindings_manifest.lua"
elif [[ -f "$script_dir/../dotfiles/hypr/keybindings_manifest.lua" ]]; then
    manifest_path="$script_dir/../dotfiles/hypr/keybindings_manifest.lua"
fi

if [[ -z "$manifest_path" || ! -f "$manifest_path" ]]; then
    printf '%s\n' "Error: Keybindings manifest not found." >&2
    exit 1
fi

manifest_dir="$(dirname -- "$manifest_path")"
if [[ -f "$manifest_dir/effective_bindings.lua" ]]; then
    effective_lua="$manifest_dir/effective_bindings.lua"
else
    effective_lua="$script_dir/../dotfiles/hypr/effective_bindings.lua"
fi

if [[ ! -f "$effective_lua" ]]; then
    printf '%s\n' "Error: effective_bindings.lua loader not found." >&2
    exit 1
fi

effective_dir="$(dirname -- "$effective_lua")"
export LUA_PATH="$manifest_dir/?.lua;$effective_dir/?.lua;${LUA_PATH:-;;}"
lua_bin="$(command -v luajit 2>/dev/null || command -v lua 2>/dev/null || true)"
if [[ -z "$lua_bin" ]]; then
    printf '%s\n' "Error: Lua interpreter not found." >&2
    exit 1
fi

get_provider() {
    if [[ -n "${PROVIDER_OVERRIDE:-}" ]]; then
        printf '%s\n' "$PROVIDER_OVERRIDE"
        return 0
    fi
    if [[ -n "${KEYBINDINGS_TEST_PROVIDER:-}" ]]; then
        printf '%s\n' "$KEYBINDINGS_TEST_PROVIDER"
        return 0
    fi
    if [[ -n "${HOTKEYS_TEST_PROVIDER:-}" ]]; then
        printf '%s\n' "$HOTKEYS_TEST_PROVIDER"
        return 0
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/workstation/desktop.conf"
    if [[ -f "$config_file" ]]; then
        local provider
        provider="$(grep -E '^[[:space:]]*(keybindings|hotkeys)[._]provider[[:space:]]*=' "$config_file" 2>/dev/null |
            tail -n 1 | cut -d '=' -f2 | tr -d ' "[:space:]' || true)"
        if [[ -n "$provider" ]]; then
            printf '%s\n' "$provider"
            return 0
        fi
    fi
    printf '%s\n' "aurelia"
}

get_user_actions_path() {
    printf '%s\n' "${KEYBINDINGS_USER_ACTIONS:-${USER_ACTIONS_PATH:-}}"
}
