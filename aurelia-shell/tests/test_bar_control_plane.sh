#!/usr/bin/env bash

# T40 Omarchy-compatible Aurelia bar control-plane contract. CLI calls are
# captured by a fake resident shell and config operations use an isolated
# ShellConfig state file; no live bar or user configuration is changed.

set -Eeuo pipefail

section "Aurelia Bar Control Plane"

bar_cli="$ROOT/bin/aurelia-bar"
bar_module="$ROOT/bin/lib/aurelia-plugin/bar.sh"
shell_qml="$ROOT/shell.qml"
config_qml="$ROOT/services/ShellConfig.qml"
bar_operations_qml="$ROOT/services/BarConfigOperations.qml"
bar_control_qml="$ROOT/services/BarControlRegistry.qml"
services_qmldir="$ROOT/services/qmldir"

if [[ -x "$bar_cli" && -f "$bar_module" ]] &&
   grep -Fq 'use <plugin-id>' "$bar_module" &&
   grep -Fq 'reset' "$bar_module" &&
   grep -Fq 'defaults' "$bar_module" &&
   grep -Fq 'position <top|bottom|left|right>' "$bar_module" &&
   grep -Fq 'transparent <true|false|toggle>' "$bar_module" &&
   grep -Fq 'aurelia_bar_use' "$bar_module" &&
   grep -Fq 'aurelia_bar_reset' "$bar_module" &&
   grep -Fq 'aurelia_bar_defaults' "$bar_module" &&
   grep -Fq 'aurelia_bar_position' "$bar_module" &&
   grep -Fq 'aurelia_bar_transparent' "$bar_module"; then
    pass "[static] Aurelia bar CLI exposes the complete reference command vocabulary"
else
    fail "[static] Aurelia bar CLI command vocabulary or implementation is incomplete"
fi

if grep -Fq 'property BarConfigOperations barOperations' "$config_qml" &&
   grep -Fq 'BarConfigOperations 1.0 BarConfigOperations.qml' "$services_qmldir" &&
   grep -Fq 'BarControlRegistry 1.0 BarControlRegistry.qml' "$services_qmldir" &&
   grep -Fq 'function useBar' "$bar_operations_qml" &&
   grep -Fq 'function resetBar' "$bar_operations_qml" &&
   grep -Fq 'function restoreBarDefaults' "$bar_operations_qml" &&
   grep -Fq 'function setBarPosition' "$bar_operations_qml" &&
   grep -Fq 'function setBarTransparent' "$bar_operations_qml" &&
   grep -Fq 'function useBar' "$bar_control_qml" &&
   grep -Fq 'function restoreBarDefaults' "$bar_control_qml" &&
   grep -Fq 'function setBarPosition' "$bar_control_qml" &&
   grep -Fq 'function setBarTransparent' "$bar_control_qml" &&
   grep -Fq 'BarControlRegistry {' "$shell_qml" &&
   grep -Fq 'id: barControlRegistry' "$shell_qml" &&
   grep -Fq 'function useBar(pluginId: string)' "$shell_qml" &&
   grep -Fq 'function restoreBarDefaults()' "$shell_qml" &&
   grep -Fq 'function setBarPosition(position: string)' "$shell_qml" &&
   grep -Fq 'function setBarTransparent(value: string)' "$shell_qml"; then
    pass "[static] resident ShellConfig, registry, and shell IPC own all bar control mutations"
else
    fail "[static] resident bar control mutation boundary is incomplete"
fi

if ! grep -Fq 'shell.json' "$bar_module" &&
   ! grep -Fq 'source_file' "$bar_module" &&
   ! grep -Fq 'mv ' "$bar_module" &&
   grep -Fq 'aurelia_bar_shell_call' "$bar_module"; then
    pass "[static] bar CLI remains an IPC client and does not edit shell state behind the resident owner"
else
    fail "[static] bar CLI contains a direct shell-state mutation shortcut"
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
        source "$1/bar.sh"
        aurelia_bar_use default
        aurelia_bar_reset
        aurelia_bar_defaults
        aurelia_bar_position bottom
        aurelia_bar_transparent toggle
        aurelia_bar_transparent false
    ' _ "$ROOT/bin/lib/aurelia-plugin"
)"

if grep -Fq 'Using aurelia.bar as the active bar' <<<"$cli_output" &&
   grep -Fq 'Reset to the built-in Aurelia bar' <<<"$cli_output" &&
   grep -Fq 'Restored the default Aurelia bar' <<<"$cli_output" &&
   grep -Fq 'Bar position set to bottom' <<<"$cli_output" &&
   grep -Fq 'Bar transparency toggled' <<<"$cli_output" &&
   grep -Fq 'Bar transparency set to false' <<<"$cli_output" &&
   [[ "$(wc -l <"$calls")" -eq 6 ]] &&
   jq -s -e '.[0].method == "useBar" and .[0].id == "aurelia.bar" and
          .[1].method == "resetBar" and
          .[2].method == "restoreBarDefaults" and
          .[3].method == "setBarPosition" and .[3].value == "bottom" and
          .[4].method == "setBarTransparent" and .[4].value == "toggle" and
          .[5].method == "setBarTransparent" and .[5].value == "false"' "$calls" >/dev/null; then
    pass "[isolated-cli] use/reset/defaults/position/transparent route exact validated IPC calls"
else
    fail "[isolated-cli] new bar commands did not produce the expected calls: $(tr '\n' ' ' <"$calls")"
fi

invalid_calls_before="$(wc -l <"$calls")"
if aurelia_bar_position diagonal >/dev/null 2>&1 ||
   aurelia_bar_transparent maybe >/dev/null 2>&1 ||
   aurelia_bar_use 'bad/id' >/dev/null 2>&1 ||
   aurelia_bar_reset extra >/dev/null 2>&1 ||
   aurelia_bar_defaults extra >/dev/null 2>&1; then
    fail "[isolated-cli] invalid bar control arguments were accepted"
elif [[ "$(wc -l <"$calls")" -eq "$invalid_calls_before" ]]; then
    pass "[isolated-cli] invalid bar control values fail closed before any shell request"
else
    fail "[isolated-cli] invalid bar control changed the IPC call stream"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] bar control-plane ShellConfig fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mkdir -p -- "$runtime_root/config/aurelia" "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/cache"
runtime_config="$runtime_root/config/aurelia/shell.json"
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
AURELIA_BAR_CONTROL_CONFIG_SOURCE="$config_qml" \
AURELIA_BAR_CONTROL_RESULT="$runtime_result" \
AURELIA_SHELL_CONFIG="$runtime_config" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-control-plane/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e '
       .useResult == "" and .usedBarId == "fixture.alt" and
       .resetResult == "" and .resetBarId == "aurelia.bar" and
       .positionResult == "" and .position == "bottom" and
       .transparentToggleResult == "" and .transparentAfterToggle == true and
       .transparentFalseResult == "" and .transparentAfterFalse == false and
       .defaultsResult == "" and .defaultsAgainResult == "" and
       .defaultsByteStable == true and
       .defaultRight == ["aurelia.tray", "aurelia.network", "aurelia.audio", "aurelia.bluetooth", "aurelia.monitor", "aurelia.screenshot", "aurelia.power"] and
       .pluginPreserved == true and .defaultBarEnabled == true and
       .unknownStatePreserved == true and
       .invalidPositionStable == true and .invalidTransparentStable == true
   ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] bar controls are idempotent, preserve unrelated state, and restore canonical defaults"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    if grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin|Operation not permitted' "$runtime_log"; then
        pass "[skipped:isolated-runtime] bar control-plane fixture cannot create a disposable runtime backend"
    else
        fail "[isolated-runtime] bar control-plane fixture failed (status=$runtime_status): $details"
    fi
fi
