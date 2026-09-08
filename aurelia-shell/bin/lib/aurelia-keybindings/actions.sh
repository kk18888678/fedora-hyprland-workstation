#!/usr/bin/env bash
# Action execution and shortcut-edit operations.
#
# Execution always receives a NUL-delimited argv stream from Lua and launches
# it as an argv array. No command string is evaluated by a shell.

# Read a structured argv stream without losing the producer's exit status.
# Process substitution deliberately hides that status from a consuming loop;
# a coprocess preserves both arbitrary argument bytes (including spaces) and
# the explicit unavailable/non-runnable classification returned by Lua.
aurelia_read_nul_argv() {
    local producer="$1"
    shift
    local argv_fd argv_pid value status=0
    AURELIA_ACTION_ARGV=()

    coproc aurelia_argv_stream { "$producer" "$@" 2>/dev/null; }
    argv_fd="${aurelia_argv_stream[0]}"
    argv_pid="$aurelia_argv_stream_PID"
    while IFS= read -r -d '' value <&"$argv_fd"; do
        AURELIA_ACTION_ARGV+=("$value")
    done
    exec {argv_fd}<&-
    wait "$argv_pid" || status=$?
    AURELIA_ACTION_ARGV_STATUS="$status"
    return "$status"
}

aurelia_read_action_argv() {
    aurelia_read_nul_argv get_action_argv "$1"
}

aurelia_read_application_argv() {
    aurelia_read_nul_argv get_application_launch_argv "$1"
}

aurelia_read_path_argv() {
    aurelia_read_nul_argv get_path_launch_argv "$1"
}

aurelia_spawn_detached() {
    local display_description="$1"
    local log_message="$2"
    shift 2
    local -a command_argv=("$@")

    if [[ "${#command_argv[@]}" -eq 0 ]]; then
        printf '%s\n' "Error: Empty structured launch command." >&2
        return 1
    fi

    local executable="${command_argv[0]}"
    if [[ "$executable" == /* ]]; then
        if [[ ! -x "$executable" || -d "$executable" ]]; then
            log_event "ERROR" "$log_message failed: command '$executable' is not executable" "run"
            notify_user critical "Launch Failed" "Command not found: $executable"
            printf 'Error: Command "%s" is not installed or not executable.\n' "$executable" >&2
            return 1
        fi
    elif ! command -v "$executable" >/dev/null 2>&1; then
        log_event "ERROR" "$log_message failed: command '$executable' not found" "run"
        notify_user critical "Launch Failed" "Command not found: $executable"
        printf 'Error: Command "%s" is not installed or not executable.\n' "$executable" >&2
        return 1
    fi

    if command -v setsid >/dev/null 2>&1; then
        setsid -f "${command_argv[@]}" </dev/null >/dev/null 2>&1
    elif command -v nohup >/dev/null 2>&1; then
        (
            nohup "${command_argv[@]}" </dev/null >/dev/null 2>&1 &
        )
    else
        log_event "ERROR" "$log_message failed: neither setsid nor nohup is available" "run"
        printf '%s\n' "Error: No supported detached process launcher is available." >&2
        return 1
    fi

    local argv_summary=""
    local quoted_arg=""
    for quoted_arg in "${command_argv[@]}"; do
        local rendered_arg=""
        printf -v rendered_arg '%q' "$quoted_arg"
        argv_summary+="${argv_summary:+ }$rendered_arg"
    done
    log_event "INFO" "$log_message via structured argv: $argv_summary" "run"
    printf '%s\n' "Running: $display_description"
    return 0
}

execute_action() {
    local action_id="$1"
    local description="$2"
    local -a command_argv=()
    local status=0

    aurelia_read_action_argv "$action_id" || status=$?
    command_argv=("${AURELIA_ACTION_ARGV[@]}")

    if [[ "$status" -ne 0 || "${#command_argv[@]}" -eq 0 ]]; then
        printf 'UNAVAILABLE:%s\n' "$description"
        return 2
    fi

    aurelia_spawn_detached \
        "$description" \
        "Action '$action_id' ($description)" \
        "${command_argv[@]}"
}

execute_application() {
    local desktop_id="$1"
    local -a command_argv=()
    local status=0

    aurelia_read_application_argv "$desktop_id" || status=$?
    command_argv=("${AURELIA_ACTION_ARGV[@]}")
    if [[ "$status" -ne 0 || "${#command_argv[@]}" -eq 0 ]]; then
        printf 'Error: Application "%s" is unavailable or has no safe launch command.\n' "$desktop_id" >&2
        return 2
    fi

    local description
    description="$(get_application_description "$desktop_id" 2>/dev/null || printf '%s' "$desktop_id")"
    aurelia_spawn_detached \
        "$description" \
        "Application '$desktop_id' ($description)" \
        "${command_argv[@]}"
}

execute_open_path() {
    local path="$1"
    local -a command_argv=()
    local status=0

    if [[ "$path" != /* || "$path" == "/" || "$path" == *$'\n'* || "$path" == *$'\r'* ]]; then
        printf '%s\n' "Error: Path must be an existing absolute user path." >&2
        return 2
    fi
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        printf 'Error: Path does not exist: %s\n' "$path" >&2
        return 2
    fi

    aurelia_read_path_argv "$path" || status=$?
    command_argv=("${AURELIA_ACTION_ARGV[@]}")
    if [[ "$status" -ne 0 || "${#command_argv[@]}" -eq 0 ]]; then
        printf 'Error: Could not resolve a safe opener for: %s\n' "$path" >&2
        return 2
    fi

    aurelia_spawn_detached \
        "$path" \
        "Opened path '$path'" \
        "${command_argv[@]}"
}

apply_binding_edit() {
    local action_id="$1"
    local new_input="$2"
    local overrides_path="${KEYBINDINGS_OVERRIDES:-${HOTKEYS_OVERRIDES:-}}"
    local force_flag="${FORCE:-0}"

    "$lua_bin" - "$manifest_path" "$manifest_dir" "$action_id" "$new_input" "$overrides_path" "$force_flag" <<'LUA_EDIT'
local manifest_path  = arg[1]
local manifest_dir   = arg[2]
local action_id      = arg[3]
local new_input      = arg[4]
local overrides_path = arg[5]
local force_flag     = arg[6]
if overrides_path == "" then overrides_path = nil end
local force = (force_flag == "1" or force_flag == "true")
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local ok, result = eff.set_action_binding(action_id, new_input, manifest_path, overrides_path, nil, force)
if not ok then
    io.stderr:write(tostring(result) .. "\n")
    os.exit(1)
end
print(tostring(result))
LUA_EDIT
}

lookup_action_description() {
    local target_id="$1"
    get_action_description "$target_id"
}

run_test_action() {
    local test_action="$1"
    local target_id="${KEYBINDINGS_TEST_ID:-${HOTKEYS_TEST_ID:-}}"
    local target_input="${KEYBINDINGS_TEST_INPUT:-${HOTKEYS_TEST_INPUT:-}}"
    local -a command_argv=()
    local value

    case "$test_action" in
        list)
            get_tsv_rows
            ;;
        apps)
            get_app_rows
            ;;
        assign_app)
            if "$lua_bin" - "$manifest_path" "$manifest_dir" "$target_id" "$target_input" <<'LUA_ASSIGN'
local manifest_path = arg[1]
local manifest_dir  = arg[2]
local desktop_id    = arg[3]
local new_input     = arg[4]
package.path = manifest_dir .. "/?.lua;" .. package.path
local eff = require("effective_bindings")
local ok, result = eff.assign_application_shortcut(desktop_id, new_input, manifest_path)
if not ok then
    io.stderr:write(tostring(result) .. "\n")
    os.exit(1)
end
print(tostring(result))
LUA_ASSIGN
            then
                printf '%s\n' "ASSIGN_APP_OK"
            else
                printf '%s\n' "ASSIGN_APP_FAIL" >&2
                return 1
            fi
            ;;
        run|run_argv)
            aurelia_read_action_argv "$target_id" || true
            command_argv=("${AURELIA_ACTION_ARGV[@]}")
            if [[ "${#command_argv[@]}" -gt 0 ]]; then
                if [[ "$test_action" == "run_argv" ]]; then
                    printf '%s\n' "${command_argv[@]}"
                else
                    printf 'RUN:%s\n' "${command_argv[*]}"
                    if [[ "${KEYBINDINGS_TEST_EXEC:-${HOTKEYS_TEST_EXEC:-0}}" == "1" ]]; then
                        nohup "${command_argv[@]}" >/dev/null 2>&1 &
                    fi
                fi
            else
                local description
                description="$(get_action_description "$target_id" 2>/dev/null || true)"
                if [[ -z "$description" ]]; then
                    printf '%s\n' "ERROR: Action not found: $target_id" >&2
                    return 1
                fi
                if [[ "$test_action" != "run_argv" ]]; then
                    printf 'UNAVAILABLE:%s\n' "$description"
                fi
                return 2
            fi
            ;;
        edit|conflict|invalid)
            if err_msg="$(apply_binding_edit "$target_id" "$target_input" 2>&1)"; then
                printf '%s\n' "EDIT_OK"
            else
                printf 'EDIT_FAIL: %s\n' "$err_msg" >&2
                return 1
            fi
            ;;
        unset)
            if err_msg="$(apply_binding_edit "$target_id" "none" 2>&1)"; then
                printf '%s\n' "UNSET_OK"
            else
                printf 'UNSET_FAIL: %s\n' "$err_msg" >&2
                return 1
            fi
            ;;
        reset)
            if err_msg="$(apply_binding_edit "$target_id" "default" 2>&1)"; then
                printf '%s\n' "RESET_OK"
            else
                printf 'RESET_FAIL: %s\n' "$err_msg" >&2
                return 1
            fi
            ;;
        provider)
            get_provider
            ;;
        quit)
            return 0
            ;;
        *)
            printf 'Unknown TEST_ACTION: %s\n' "$test_action" >&2
            return 1
            ;;
    esac
}
