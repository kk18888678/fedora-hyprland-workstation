#!/usr/bin/env bash
# Persistent bar visibility command adapter. The standalone writer owns the
# state transition so the aurelia-bar CLI and the dedicated shortcut share one
# implementation.

aurelia_bar_hidden() {
    local operation="${1:-toggle}"
    local writer="${AURELIA_BAR_HIDDEN_WRITER:-${script_dir:-}/aurelia-bar-hidden}"
    [[ "$operation" =~ ^(on|off|toggle)$ ]] || {
        aurelia_plugin_fail "hidden must be on, off, or toggle"
        return 1
    }
    (( $# == 1 )) || { aurelia_plugin_fail "hidden takes a single value"; return 1; }
    [[ "$writer" == /* && -x "$writer" ]] || {
        aurelia_plugin_fail "aurelia-bar-hidden writer is unavailable"
        return 1
    }
    "$writer" "$operation"
}
