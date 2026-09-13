#!/usr/bin/env bash
# User-facing Aurelia bar placement and widget-setting commands.

print_aurelia_bar_help() {
    cat <<'USAGE'
Usage: aurelia-bar <command> [arguments]

Commands:
  use <plugin-id>                         Use a bar option as the active bar
  reset                                    Return to the built-in Aurelia bar
  defaults                                 Restore the shipped bar defaults
  position <top|bottom|left|right>         Set bar position
  transparent <true|false|toggle>          Set/toggle bar transparency
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

aurelia_bar_use() {
    local plugin_id="${1:-}"
    [[ -n "$plugin_id" ]] || { aurelia_plugin_fail "use requires a bar plugin id"; return 1; }
    (( $# == 1 )) || { aurelia_plugin_fail "use takes a single bar plugin id"; return 1; }
    if [[ "$plugin_id" == "default" || "$plugin_id" == "built-in" ]]; then
        plugin_id="aurelia.bar"
    fi
    aurelia_plugin_require_id "$plugin_id" || return 1
    local result
    result="$(aurelia_bar_shell_call useBar "$plugin_id")" || return 1
    [[ "$result" == "ok" ]] || { aurelia_plugin_fail "$result"; return 1; }
    printf 'Using %s as the active bar\n' "$plugin_id"
}

aurelia_bar_reset() {
    (( $# == 0 )) || { aurelia_plugin_fail "reset takes no arguments"; return 1; }
    local result
    result="$(aurelia_bar_shell_call resetBar)" || return 1
    [[ "$result" == "ok" ]] || { aurelia_plugin_fail "$result"; return 1; }
    printf '%s\n' "Reset to the built-in Aurelia bar"
}

aurelia_bar_defaults() {
    (( $# == 0 )) || { aurelia_plugin_fail "defaults takes no arguments"; return 1; }
    local result
    result="$(aurelia_bar_shell_call restoreBarDefaults)" || return 1
    [[ "$result" == "ok" ]] || { aurelia_plugin_fail "$result"; return 1; }
    printf '%s\n' "Restored the default Aurelia bar"
}

aurelia_bar_position() {
    local position="${1:-}"
    [[ -n "$position" ]] || { aurelia_plugin_fail "position is required"; return 1; }
    (( $# == 1 )) || { aurelia_plugin_fail "position takes a single value"; return 1; }
    [[ "$position" =~ ^(top|bottom|left|right)$ ]] || {
        aurelia_plugin_fail "position must be top, bottom, left, or right"
        return 1
    }
    local result
    result="$(aurelia_bar_shell_call setBarPosition "$position")" || return 1
    [[ "$result" == "ok" ]] || { aurelia_plugin_fail "$result"; return 1; }
    printf 'Bar position set to %s\n' "$position"
}

aurelia_bar_transparent() {
    local value="${1:-}"
    [[ -n "$value" ]] || { aurelia_plugin_fail "transparent is required"; return 1; }
    (( $# == 1 )) || { aurelia_plugin_fail "transparent takes a single value"; return 1; }
    [[ "$value" =~ ^(true|false|toggle)$ ]] || {
        aurelia_plugin_fail "transparent must be true, false, or toggle"
        return 1
    }
    local result
    result="$(aurelia_bar_shell_call setBarTransparent "$value")" || return 1
    [[ "$result" == "ok" ]] || { aurelia_plugin_fail "$result"; return 1; }
    if [[ "$value" == "toggle" ]]; then
        printf '%s\n' "Bar transparency toggled"
    else
        printf 'Bar transparency set to %s\n' "$value"
    fi
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
        use)
            aurelia_bar_use "$@"
            ;;
        reset)
            aurelia_bar_reset "$@"
            ;;
        defaults)
            aurelia_bar_defaults "$@"
            ;;
        position)
            aurelia_bar_position "$@"
            ;;
        transparent)
            aurelia_bar_transparent "$@"
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
