#!/usr/bin/env bash
# CLI parsing and command routing for Aurelia Keybindings.
#
# This module owns user-facing command semantics only. Data projections,
# mutations, diagnostics, and IPC lifecycle live in their respective modules.

print_keybindings_help() {
    printf '%s\n' 'Usage: aurelia-shell-keybindings [toggle|json|apps|files <query>|launch-app <desktop-id>|open-path <absolute-path>|add-app <id>|remove-app <id>|add-exec <id> <name> <path> [args...]|remove-action <id>|set <id> <key>|unset <id>|run <id>|choose-file|complete-path <prefix>]'
}

handle_meta_subcommand() {
    case "${1:-}" in
        diagnostics|--diagnostics)
            shift
            if [[ "${1:-}" == "runtime" ]]; then
                shift
                run_diagnostics_runtime "$@"
                return $?
            fi
            local aurelia_bin=""
            if aurelia_bin="$(resolve_aurelia_bin)"; then
                exec "$aurelia_bin" diagnostics "$@"
            fi
            printf '%s\n' "Error: workstation-aurelia command not found; cannot delegate diagnostics." >&2
            return 1
            ;;
        preference|--preference|pref)
            shift
            local preference_bin=""
            if preference_bin="$(resolve_aurelia_bin)"; then
                exec "$preference_bin" preference "$@"
            fi
            printf '%s\n' "Error: workstation-aurelia command not found; cannot delegate preference." >&2
            return 1
            ;;
        motion|--motion)
            shift
            local motion_bin=""
            if motion_bin="$(resolve_aurelia_bin)"; then
                exec "$motion_bin" motion "$@"
            fi
            printf '%s\n' "Error: workstation-aurelia command not found; cannot delegate motion." >&2
            return 1
            ;;
        *)
            return 2
            ;;
    esac
}

parse_keybindings_args() {
    SUBCOMMAND=""
    TARGET_ID=""
    NEW_KEY=""
    EXEC_NAME=""
    EXEC_PATH=""
    EXEC_ARGV=()
    PROVIDER_OVERRIDE=""
    FORCE=0

    local -a remaining_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider=legacy)
                printf '%s\n' "Error: Legacy provider has been removed." >&2
                return 1
                ;;
            --provider=*)
                PROVIDER_OVERRIDE="${1#*=}"
                shift
                ;;
            --provider)
                if [[ "${2:-}" == "legacy" ]]; then
                    printf '%s\n' "Error: Legacy provider has been removed." >&2
                    return 1
                fi
                PROVIDER_OVERRIDE="${2:-}"
                if [[ $# -gt 1 ]]; then
                    shift 2
                else
                    shift
                fi
                ;;
            json|--json)
                SUBCOMMAND="json"
                shift
                ;;
            apps|--apps)
                SUBCOMMAND="apps"
                shift
                ;;
            files|--files)
                SUBCOMMAND="files"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            launch-app|--launch-app)
                SUBCOMMAND="launch-app"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            open-path|--open-path)
                SUBCOMMAND="open-path"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            add-app|--add-app)
                SUBCOMMAND="add-app"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            remove-app|--remove-app)
                SUBCOMMAND="remove-app"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            add-exec|--add-exec)
                SUBCOMMAND="add-exec"
                TARGET_ID="${2:-}"
                EXEC_NAME="${3:-}"
                EXEC_PATH="${4:-}"
                if [[ $# -ge 4 ]]; then
                    shift 4
                else
                    shift "$#"
                fi
                EXEC_ARGV=("$@")
                shift "$#"
                ;;
            remove-action|--remove-action)
                SUBCOMMAND="remove-action"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            validate-shortcut|--validate-shortcut)
                SUBCOMMAND="validate-shortcut"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            run|--run)
                SUBCOMMAND="run"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            choose-file|--choose-file|browse-file)
                SUBCOMMAND="choose-file"
                shift
                ;;
            complete-path|--complete-path)
                SUBCOMMAND="complete-path"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            set|--set)
                SUBCOMMAND="set"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                    NEW_KEY="$1"
                    shift
                fi
                ;;
            unset|--unset)
                SUBCOMMAND="unset"
                TARGET_ID="${2:-}"
                if [[ $# -gt 1 ]]; then shift 2; else shift; fi
                ;;
            --force|-f)
                FORCE=1
                shift
                ;;
            toggle|--toggle)
                SUBCOMMAND="toggle"
                shift
                ;;
            help|-h|--help)
                SUBCOMMAND="help"
                shift
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#remaining_args[@]} -gt 0 ]]; then
        printf 'Error: Unrecognized command or option: %s\n' "${remaining_args[0]}" >&2
        return 1
    fi
}

run_explicit_command() {
    case "$SUBCOMMAND" in
        help)
            print_keybindings_help
            return 0
            ;;
        json)
            get_json_rows
            return $?
            ;;
        apps)
            get_apps_json
            return $?
            ;;
        files)
            get_files_json "$TARGET_ID"
            return $?
            ;;
        choose-file)
            choose_file
            return $?
            ;;
        complete-path)
            complete_path "$TARGET_ID"
            return $?
            ;;
        validate-shortcut)
            validate_shortcut "$TARGET_ID"
            return $?
            ;;
        add-app)
            add_application "$TARGET_ID"
            return $?
            ;;
        add-exec)
            add_executable "$TARGET_ID" "$EXEC_NAME" "$EXEC_PATH" "${EXEC_ARGV[@]}"
            return $?
            ;;
        remove-app|remove-action)
            remove_user_action "$TARGET_ID" "$SUBCOMMAND"
            return $?
            ;;
        launch-app)
            if [[ -z "$TARGET_ID" || ! "$TARGET_ID" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*\.desktop$ ]]; then
                printf '%s\n' "Error: Invalid desktop application ID for launch-app" >&2
                return 1
            fi
            ;;
        open-path)
            if [[ -z "$TARGET_ID" || "$TARGET_ID" != /* || "$TARGET_ID" == "/" ]]; then
                printf '%s\n' "Error: open-path requires an absolute non-root path" >&2
                return 1
            fi
            ;;
        run|set|unset)
            if [[ -z "$TARGET_ID" ]]; then
                printf '%s\n' "Error: Missing action ID for $SUBCOMMAND" >&2
                return 1
            fi
            if [[ ! "$TARGET_ID" =~ ^[a-zA-Z0-9_.:-]+$ ]]; then
                printf '%s\n' "Error: Invalid action ID: $TARGET_ID" >&2
                return 1
            fi
            ;;
        "")
            return 2
            ;;
        toggle)
            return 2
            ;;
        *)
            printf 'Error: Unsupported command: %s\n' "$SUBCOMMAND" >&2
            return 1
            ;;
    esac

    case "$SUBCOMMAND" in
        launch-app)
            execute_application "$TARGET_ID"
            ;;
        open-path)
            execute_open_path "$TARGET_ID"
            ;;
        run)
            local description=""
            if ! description="$(lookup_action_description "$TARGET_ID" 2>/dev/null)"; then
                printf '%s\n' "Error: Unknown action ID: $TARGET_ID" >&2
                return 1
            fi
            execute_action "$TARGET_ID" "${description:-$TARGET_ID}"
            ;;
        unset)
            local unset_error=""
            if unset_error="$(apply_binding_edit "$TARGET_ID" "none" 2>&1)"; then
                log_event "INFO" "Successfully unset shortcut for '$TARGET_ID'" "unset"
                printf '%s\n' "UNSET_OK"
                return 0
            fi
            log_event "ERROR" "Failed to unset shortcut for '$TARGET_ID': $unset_error" "unset"
            printf 'UNSET_FAIL: %s\n' "$unset_error" >&2
            return 1
            ;;
        set)
            if [[ -z "$NEW_KEY" ]]; then
                NEW_KEY="${KEYBINDINGS_CAPTURE_MOCK_INPUT:-${HOTKEYS_CAPTURE_MOCK_INPUT:-}}"
            fi
            if [[ -z "$NEW_KEY" ]]; then
                printf '%s\n' "Error: Missing key combination for set" >&2
                return 1
            fi
            local set_error=""
            if set_error="$(apply_binding_edit "$TARGET_ID" "$NEW_KEY" 2>&1)"; then
                log_event "INFO" "Successfully set shortcut for '$TARGET_ID' to '$NEW_KEY'" "set"
                printf '%s\n' "SET_OK"
                return 0
            fi
            log_event "ERROR" "Failed to set shortcut for '$TARGET_ID' to '$NEW_KEY': $set_error" "set"
            printf '%s\n' "$set_error" >&2
            return 1
            ;;
    esac
}

run_test_command() {
    local test_action="${KEYBINDINGS_TEST_ACTION:-${HOTKEYS_TEST_ACTION:-}}"
    [[ -n "$test_action" ]] || return 2
    if [[ "$test_action" == "json" ]]; then
        get_json_rows
        return $?
    fi
    run_test_action "$test_action"
}

main() {
    local meta_status
    if handle_meta_subcommand "$@"; then
        return 0
    else
        meta_status=$?
        if [[ "$meta_status" -ne 2 ]]; then
            return "$meta_status"
        fi
    fi

    parse_keybindings_args "$@" || return $?

    if [[ "$SUBCOMMAND" == "json" || "$SUBCOMMAND" == "apps" ||
          "$SUBCOMMAND" == "files" || "$SUBCOMMAND" == "launch-app" ||
          "$SUBCOMMAND" == "open-path" ||
          "$SUBCOMMAND" == "choose-file" || "$SUBCOMMAND" == "complete-path" ||
          "$SUBCOMMAND" == "validate-shortcut" || "$SUBCOMMAND" == "add-app" ||
          "$SUBCOMMAND" == "add-exec" || "$SUBCOMMAND" == "remove-app" ||
          "$SUBCOMMAND" == "remove-action" || "$SUBCOMMAND" == "run" ||
          "$SUBCOMMAND" == "set" || "$SUBCOMMAND" == "unset" ||
          "$SUBCOMMAND" == "help" ]]; then
        run_explicit_command
        return $?
    fi

    # Preserve the non-interactive text projection used by legacy callers and
    # diagnostics. It must be decided before test hooks or IPC dispatch.
    if [[ "${KEYBINDINGS_FORCE_STDOUT:-${HOTKEYS_FORCE_STDOUT:-0}}" == "1" ]]; then
        render_output
        return 0
    fi

    if [[ -n "${KEYBINDINGS_TEST_ACTION:-${HOTKEYS_TEST_ACTION:-}}" ]]; then
        # A test hook may legitimately return the same classified status 2
        # used for unavailable actions. Do not interpret that as "no hook" and
        # fall through into live Quickshell dispatch.
        run_test_command
        return $?
    fi

    toggle_aurelia
}
