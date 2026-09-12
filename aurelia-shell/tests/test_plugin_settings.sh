#!/usr/bin/env bash

# T13 generic plugin instance settings checks.

set -Eeuo pipefail

section "Aurelia Generic Plugin Instance Settings"

config_root="$ROOT/services/ShellConfig.qml"
registry_root="$ROOT/services/PluginRegistry.qml"
host_root="$ROOT/services/PluginHost.qml"
shell_root="$ROOT/shell.qml"
slot_root="$ROOT/plugins/aurelia.bar/BarWidgetSlot.qml"

if grep -q 'function validateJsonValue' "$config_root" &&
   grep -q 'function updateEntryInline' "$config_root" &&
   grep -q 'function resetEntryInline' "$config_root" &&
   grep -q 'function settingsForEntry' "$config_root" &&
   grep -q 'settingsMaxBytes' "$config_root" &&
   grep -q 'function updateEntryInline' "$registry_root" &&
   grep -q 'function resetEntryInline' "$registry_root" &&
   grep -q 'function updateEntryInline' "$shell_root" &&
   grep -q 'function resetEntryInline' "$shell_root"; then
    pass "[static] ShellConfig, PluginRegistry, and shell IPC expose generic settings update/reset ownership"
else
    fail "[static] generic settings API wiring is incomplete"
fi

if grep -q 'refreshPluginSettings' "$host_root" &&
   grep -q 'aureliaSettingsChanged' "$host_root" &&
   grep -q 'settingsForEntry' "$host_root" &&
   [[ "$(grep -c 'onSettingsChanged' "$slot_root")" -eq 1 ]]; then
    pass "[static] live settings changes refresh resident objects without duplicate bar property handlers"
else
    fail "[static] live settings refresh boundary is incomplete or duplicated"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] generic plugin settings QuickShell fixtures (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mkdir -p -- "$runtime_root/config/aurelia" "$runtime_root/plugin-state"
config_path="$runtime_root/config/aurelia/shell.json"
printf '%s\n' '{"version":1,"owned":true}' >"$runtime_root/plugin-state/owned.json"
owned_hash_before="$(sha256sum "$runtime_root/plugin-state/owned.json" | awk '{print $1}')"
settings_result="$runtime_root/settings-result.json"
settings_log="$runtime_root/settings.log"
settings_status=0
AURELIA_PLUGIN_SETTINGS_CONFIG_SOURCE="$config_root" \
AURELIA_PLUGIN_SETTINGS_RESULT="$settings_result" \
AURELIA_SHELL_CONFIG="$config_path" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-settings/shell.qml" \
    >"$settings_log" 2>&1 || settings_status=$?
owned_hash_after="$(sha256sum "$runtime_root/plugin-state/owned.json" | awk '{print $1}')"
settings_mode="$(stat -c '%a' "$config_path" 2>/dev/null || true)"

if [[ "$settings_status" -eq 0 ]] && [[ -s "$settings_result" ]] &&
   [[ "$owned_hash_before" == "$owned_hash_after" ]] &&
   [[ "$settings_mode" == "600" ]] &&
   jq -e '
        .effectiveBefore.format == "user" and
        .effectiveBefore.shipped == true and
        .updateBar == true and
        .unchangedUpdate == false and
        .updatePanel == true and
        .rejectedFunction == false and
        .rejectedLarge == false and
        .ambiguousUpdate == false and
        .explicitUpdate == true and
        .resetMulti == true and
        .resetAgain == false and
        .selectorRejected == false and
        .widget.id == "fixture.widget" and
        .widget.format == "updated" and
        .widget.newValue == "kept" and
        .widget.unknownKeep == 9 and
        .multiB.id == "fixture.multi" and
        .multiB.instanceId == "multi-b" and
        (.multiB.mode == null) and
        .panel.id == "fixture.panel" and
        .panel.mode == "compact" and
        .panel.pluginUnknown == 7 and
        .panel.panelUnknown == 8 and
        .centerCount == 3 and
        .userOwned == true
    ' "$settings_result" >/dev/null; then
    pass "[isolated-runtime] bar/panel updates, bounded JSON rejection, duplicate addressing, reset, and plugin-state separation behave correctly"
else
    details="$(tr '\n' ' ' <"$settings_log")"
    if [[ -s "$settings_result" ]]; then details="$details result=$(tr '\n' ' ' <"$settings_result")"; fi
    fail "[isolated-runtime] generic settings fixture failed (status=$settings_status mode=$settings_mode): $details"
fi

host_result="$runtime_root/host-result.json"
host_log="$runtime_root/host.log"
host_status=0
AURELIA_PLUGIN_SETTINGS_HOST_SOURCE="$host_root" \
AURELIA_PLUGIN_SETTINGS_HOST_RESULT="$host_result" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/host-runtime" \
XDG_STATE_HOME="$runtime_root/host-state" \
XDG_CONFIG_HOME="$runtime_root/host-config" \
XDG_CACHE_HOME="$runtime_root/host-cache" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-settings-host/shell.qml" \
    >"$host_log" 2>&1 || host_status=$?

if [[ "$host_status" -eq 0 ]] && [[ -s "$host_result" ]] &&
   jq -e '.settings.mode == "refreshed" and .settings.preserved == 11 and .refreshes == 1' \
       "$host_result" >/dev/null; then
    pass "[isolated-runtime] resident plugin settings are refreshed in place through the narrow host boundary"
else
    details="$(tr '\n' ' ' <"$host_log")"
    if [[ -s "$host_result" ]]; then details="$details result=$(tr '\n' ' ' <"$host_result")"; fi
    fail "[isolated-runtime] resident settings refresh fixture failed (status=$host_status): $details"
fi
