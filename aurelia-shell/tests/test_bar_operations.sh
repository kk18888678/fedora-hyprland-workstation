#!/usr/bin/env bash

# T12 bar placement, movement, settings, and enablement checks.

set -Eeuo pipefail

section "Aurelia Bar Placement and Settings Operations"

config_root="$ROOT/services/ShellConfig.qml"
registry_root="$ROOT/services/PluginRegistry.qml"
shell_root="$ROOT/shell.qml"
plugin_cli_root="$ROOT/bin/lib/aurelia-plugin/main.sh"
placement_root="$ROOT/bin/lib/aurelia-plugin/placement.sh"
bar_cli_root="$ROOT/bin/lib/aurelia-plugin/bar.sh"

if grep -q 'function enablePlugin' "$config_root" &&
   grep -q 'function moveBarWidget' "$config_root" &&
   grep -q 'function setBarWidget' "$config_root" &&
   grep -q 'function validatePlacement' "$config_root" &&
   grep -q 'serializeConfig(normalized)' "$config_root" &&
   grep -q 'function enablePlugin' "$registry_root" &&
   grep -q 'function putBarWidget' "$shell_root" &&
   grep -q 'function moveBarWidget' "$shell_root" &&
   grep -q 'function setBarWidget' "$shell_root"; then
    pass "[static] ShellConfig, PluginRegistry, and shell IPC expose host-owned placement operations"
else
    fail "[static] host-owned placement operation wiring is incomplete"
fi

if [[ -x "$ROOT/bin/aurelia-bar" ]] &&
   grep -q 'aurelia_plugin_parse_placement' "$plugin_cli_root" &&
   grep -q 'enablePlugin' "$plugin_cli_root" &&
   grep -q 'putBarWidget' "$bar_cli_root" &&
   grep -q 'moveBarWidget' "$bar_cli_root" &&
   grep -q 'setBarWidget' "$bar_cli_root" &&
   grep -q 'fromSection' "$placement_root"; then
    pass "[static] plugin enable and dedicated bar CLI preserve the Omarchy command split and placement vocabulary"
else
    fail "[static] placement CLI boundary is incomplete"
fi

cli_root="$(mktemp -d)"
trap 'rm -rf -- "$cli_root" 2>/dev/null || true' RETURN
cp -- "$ROOT/tests/fixtures/bar-cli/aurelia-shell" "$cli_root/aurelia-shell"
chmod 0755 "$cli_root/aurelia-shell"
calls="$cli_root/calls.jsonl"
touch "$calls"

cli_output="$(
    AURELIA_DEVELOPMENT_MODE=1 \
    AURELIA_PLUGIN_BIN_DIR="$cli_root" \
    AURELIA_BAR_CLI_CALLS="$calls" \
    bash -c '
        set -Eeuo pipefail
        source "$1/common.sh"
        source "$1/placement.sh"
        source "$1/main.sh"
        source "$1/bar.sh"
        aurelia_plugin_main enable fixture.widget --section right --index 1
        aurelia_bar_put fixture.widget --after fixture.clock
        aurelia_bar_move fixture.widget --section right --index 0 --from-section left --from-index 2
        aurelia_bar_set fixture.widget format 24 --json --section right --index 0
    ' _ "$ROOT/bin/lib/aurelia-plugin"
)"

if grep -q 'Enabled and placed fixture.widget.' <<<"$cli_output" &&
   grep -q 'fixture.widget is on the bar' <<<"$cli_output" &&
   grep -q 'Moved fixture.widget' <<<"$cli_output" &&
   grep -q 'Set format on fixture.widget' <<<"$cli_output" &&
   [[ "$(wc -l <"$calls")" -eq 4 ]] &&
   jq -e '
       select(.method == "enablePlugin" and .id == "fixture.widget" and
              ((.placement | fromjson).section == "right") and
              ((.placement | fromjson).index == 1))
   ' "$calls" >/dev/null &&
   jq -e '
       select(.method == "putBarWidget" and
              ((.placement | fromjson).after == "fixture.clock"))
   ' "$calls" >/dev/null &&
   jq -e '
       select(.method == "moveBarWidget" and
              ((.placement | fromjson).section == "right") and
              ((.placement | fromjson).index == 0) and
              ((.placement | fromjson).fromSection == "left") and
              ((.placement | fromjson).fromIndex == 2))
   ' "$calls" >/dev/null &&
   jq -e '
       select(.method == "setBarWidget" and .key == "format" and
              (.value | fromjson) == 24 and
              ((.selector | fromjson).section == "right") and
              ((.selector | fromjson).index == 0))
   ' "$calls" >/dev/null; then
    pass "[isolated-cli] enable, put, move, set, positional selectors, and JSON values produce the canonical IPC requests"
else
    fail "[isolated-cli] placement CLI did not produce the expected requests: $(tr '\n' ' ' <"$calls")"
fi

if (
    AURELIA_DEVELOPMENT_MODE=1
    AURELIA_PLUGIN_BIN_DIR="$cli_root"
    AURELIA_BAR_CLI_CALLS="$calls"
    source "$ROOT/bin/lib/aurelia-plugin/common.sh"
    source "$ROOT/bin/lib/aurelia-plugin/placement.sh"
    source "$ROOT/bin/lib/aurelia-plugin/bar.sh"
    aurelia_bar_put fixture.widget --before fixture.clock --after fixture.tray
); then
    fail "[isolated-cli] parser accepted mutually exclusive before/after placement"
else
    pass "[isolated-cli] invalid placement is rejected before any shell request"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] catalog/config signal-cycle fixture (qs or timeout unavailable)"
else
    cycle_root="$(mktemp -d)"
    trap 'rm -rf -- "$cycle_root" 2>/dev/null || true' RETURN
    mkdir -p -- "$cycle_root/config/aurelia"
    cycle_result="$cycle_root/result.json"
    cycle_log="$cycle_root/runtime.log"
    cycle_status=0
    AURELIA_BAR_CYCLE_REGISTRY_SOURCE="$ROOT/services/BarWidgetRegistry.qml" \
    AURELIA_BAR_CYCLE_CONFIG_SOURCE="$ROOT/services/ShellConfig.qml" \
    AURELIA_BAR_CYCLE_RESULT="$cycle_result" \
    AURELIA_SHELL_CONFIG="$cycle_root/config/aurelia/shell.json" \
    QT_QPA_PLATFORM=offscreen \
    WAYLAND_DISPLAY="" \
    XDG_RUNTIME_DIR="$cycle_root/runtime" \
    XDG_STATE_HOME="$cycle_root/state" \
    XDG_CONFIG_HOME="$cycle_root/config" \
    XDG_CACHE_HOME="$cycle_root/cache" \
        /usr/bin/timeout --kill-after=1s 5s /usr/bin/qs --no-duplicate \
        --path "$ROOT/tests/fixtures/bar-catalog-cycle/shell.qml" \
        >"$cycle_log" 2>&1 || cycle_status=$?

    if [[ "$cycle_status" -eq 0 ]] && [[ -s "$cycle_result" ]] &&
       jq -e '
            .configChanges <= 2 and
            .feedbackSignals <= 2 and
            .centerCount == 1 and
            .remainingValue == "first"
        ' "$cycle_result" >/dev/null; then
        pass "[isolated-runtime] catalog/config signal boundary converges without recursive updates"
    else
        details="$(tr '\n' ' ' <"$cycle_log")"
        if [[ -s "$cycle_result" ]]; then details="$details result=$(tr '\n' ' ' <"$cycle_result")"; fi
        fail "[isolated-runtime] catalog/config signal-cycle fixture failed (status=$cycle_status): $details"
    fi
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] bar operations QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mkdir -p -- "$runtime_root/config/aurelia"
runtime_config="$runtime_root/config/aurelia/shell.json"
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
AURELIA_BAR_OPERATIONS_CONFIG_SOURCE="$ROOT/services/ShellConfig.qml" \
AURELIA_BAR_OPERATIONS_RESULT="$runtime_result" \
AURELIA_SHELL_CONFIG="$runtime_config" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-operations/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e '
        .enableResult == "" and
        .rightAfterEnable == ["aurelia.tray", "fixture.widget"] and
        .setResult == "" and
        .enableAgainResult == "" and
        .preservedBeforeMove == "custom" and
        .putResult == "" and
        .moveResult == "" and
        .ambiguousResult == "ambiguous widget fixture.multi" and
        .multiMoveResult == "" and
        .moveBeforeResult == "" and
        .multiSetResult == "" and
        .invalidIndexResult == "index must be a non-negative integer" and
        .invalidSectionResult == "section must be left, center, or right" and
        .invalidMoveResult == "could not find target widget missing.widget" and
        .invalidMoveStable == true and
        .disableResult == true and
        .enabledWhileDisabled == false and
        .reenableResult == true and
        .enabledAfterReenable == true and
        .leftIds == ["fixture.widget", "aurelia.workspaces"] and
        .centerIds == ["aurelia.clock", "aurelia.weather", "fixture.put", "fixture.multi"] and
        .rightIds == ["fixture.multi", "aurelia.tray"] and
        .centerInstanceIds == ["aurelia.clock", "aurelia.weather", "fixture.put", "multi-b"] and
        .rightInstanceIds == ["multi-a", "aurelia.tray"] and
        .restoredFormat == "custom" and
        .multiMode == "fast" and
        .customBarValue == "preserve" and
        .userOwned == true
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] enable-and-place, default-section fallback, idempotent placement, move/set selectors, duplicate errors, and disable/re-enable preservation behave correctly"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] bar operations fixture failed (status=$runtime_status): $details"
fi
