#!/usr/bin/env bash
# User-facing Aurelia bar placement and widget-setting commands.

print_aurelia_bar_help() {
    cat <<'USAGE'
Usage: aurelia-bar <command> [arguments]

Commands:
  put <plugin-id> [placement]             Put a widget on the bar if absent
  move <plugin-id> [placement]            Move a configured widget
  set <plugin-id> <key> <value> [--json] [placement]
                                         Set an inline widget option

Placement:
  --section <left|center|right>           Target section
  --index <n>                             Target index
  --before <plugin-id>                    Insert before a widget
  --after <plugin-id>                     Insert after a widget
  --from-section <left|center|right>      Source section for move/set
  --from-index <n>                        Source index for move/set

Use 'aurelia-plugin enable <plugin-id> [placement]' for one-step enable and
placement. Disabling remains a separate lifecycle operation.
USAGE
}

aurelia_bar_shell_call() {
    local method="$1"
    shift
    local shell_cli
    shell_cli="$(aurelia_plugin_shell_cli)" || return 1
    "$shell_cli" shell "$method" "$@"
}

aurelia_bar_put() {
    local plugin_id="${1:-}"
    [[ -n "$plugin_id" ]] || { aurelia_plugin_fail "put requires a plugin id"; return 1; }
    aurelia_plugin_require_id "$plugin_id" || return 1
    shift
    aurelia_plugin_parse_placement put 1 "$@" || return 1
    local placement result
    placement="$(aurelia_plugin_placement_json)" || return 1
    result="$(aurelia_bar_shell_call putBarWidget "$plugin_id" "$placement")" || return 1
    [[ "$result" == "ok" ]] || { aurelia_plugin_fail "$result"; return 1; }
    printf '%s\n' "$plugin_id is on the bar"
}

aurelia_bar_move() {
    local plugin_id="${1:-}"
    [[ -n "$plugin_id" ]] || { aurelia_plugin_fail "move requires a plugin id"; return 1; }
    aurelia_plugin_require_id "$plugin_id" || return 1
    shift
    aurelia_plugin_parse_placement move 1 "$@" || return 1
    local placement result
    placement="$(aurelia_plugin_placement_json)" || return 1
    result="$(aurelia_bar_shell_call moveBarWidget "$plugin_id" "$placement")" || return 1
    [[ "$result" == "ok" ]] || { aurelia_plugin_fail "$result"; return 1; }
    printf 'Moved %s\n' "$plugin_id"
}

aurelia_bar_set() {
    local plugin_id="${1:-}"
    local key="${2:-}"
    local value="${3:-}"
    [[ -n "$plugin_id" ]] || { aurelia_plugin_fail "set requires a plugin id"; return 1; }
    [[ -n "$key" ]] || { aurelia_plugin_fail "set requires a setting key"; return 1; }
    (( $# >= 3 )) || { aurelia_plugin_fail "set requires a value"; return 1; }
    aurelia_plugin_require_id "$plugin_id" || return 1
    [[ "$key" =~ ^[A-Za-z][A-Za-z0-9_.-]*$ ]] || {
        aurelia_plugin_fail "set requires a safe setting key"
        return 1
    }
    shift 3

    local value_json
    if (( $# > 0 )) && [[ "$1" == "--json" ]]; then
        shift
        value_json="$(jq -cn --argjson value "$value" '$value')" || {
            aurelia_plugin_fail "invalid JSON value: $value"
            return 1
        }
    else
        value_json="$(jq -cn --arg value "$value" '$value')" || return 1
    fi

    aurelia_plugin_parse_placement set 0 "$@" || return 1
    local placement result
    placement="$(aurelia_plugin_placement_json)" || return 1
    result="$(aurelia_bar_shell_call setBarWidget "$plugin_id" "$key" "$value_json" "$placement")" || return 1
    [[ "$result" == "ok" ]] || { aurelia_plugin_fail "$result"; return 1; }
    printf 'Set %s on %s\n' "$key" "$plugin_id"
}

aurelia_bar_main() {
    local command="${1:-help}"
    shift || true
    case "$command" in
        help|-h|--help)
            print_aurelia_bar_help
            ;;
        put)
            aurelia_bar_put "$@"
            ;;
        move)
            aurelia_bar_move "$@"
            ;;
        set)
            aurelia_bar_set "$@"
            ;;
        *)
            aurelia_plugin_fail "Unknown bar command: $command"
            print_aurelia_bar_help >&2
            return 1
            ;;
    esac
}
