#!/usr/bin/env bash

# T06 dedicated bar-widget registry and composition-boundary checks.

set -Eeuo pipefail

section "Aurelia Bar Widget Registry"

services_root="$ROOT/services"
bar_root="$ROOT/plugins/aurelia.bar"

if [[ -f "$services_root/BarWidgetRegistry.qml" ]] &&
   grep -q 'BarWidgetRegistry 1.0 BarWidgetRegistry.qml' "$services_root/qmldir" &&
   grep -q 'barWidgetRegistry: barWidgetRegistry' "$ROOT/shell.qml" &&
   grep -q 'function sync()' "$services_root/BarWidgetRegistry.qml"; then
    pass "[static] BarWidgetRegistry is a declared resident component catalogue"
else
    fail "[static] BarWidgetRegistry declaration or shell wiring is incomplete"
fi

if grep -q 'barWidgetRegistry: root.barWidgetRegistry' "$bar_root/BarWidgetRow.qml" &&
   grep -q 'barWidgetRegistry: root.barWidgetRegistry' "$bar_root/BarCenter.qml" &&
   grep -q 'property var barWidgetRegistry' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'entryPointUrl(root.pluginId)' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'if ("barWidgetRegistry" in target)' "$ROOT/services/PluginHost.qml"; then
    pass "[static] bar layout rows and slots consume the dedicated registry"
else
    fail "[static] bar-widget loader ownership is still coupled to the raw plugin registry"
fi

if grep -q 'signal pluginLoaded' "$ROOT/services/PluginHost.qml" &&
   grep -q 'signal pluginLoadFailed' "$ROOT/services/PluginHost.qml" &&
   grep -q 'signal pluginUnloaded' "$ROOT/services/PluginHost.qml" &&
   grep -q 'signal pluginReloaded' "$ROOT/services/PluginHost.qml"; then
    pass "[static] host exposes structured load, failure, unload, and reload events"
else
    fail "[static] structured PluginHost lifecycle events are incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] BarWidgetRegistry QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
expected_widgets="$(find "$ROOT/plugins" -type f -name manifest.json -print0 | xargs -0 jq -r 'select((.kinds | index("bar-widget")) != null) | .id' | sort -u | wc -l)"
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
AURELIA_BAR_REGISTRY_PLUGIN_SOURCE="$ROOT/services/PluginRegistry.qml" \
AURELIA_BAR_REGISTRY_SOURCE="$ROOT/services/BarWidgetRegistry.qml" \
AURELIA_BAR_REGISTRY_RESULT="$runtime_result" \
AURELIA_SHELL_ROOT="$ROOT" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-registry/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e --arg root "$ROOT" --argjson expected "$expected_widgets" '
        .scanState == "success" and
        .pluginCount == 21 and
        (.widgetIds | length == $expected) and
        (.widgetIds | index("aurelia.clock")) and
        (.widgetIds | index("aurelia.notifications")) and
        (.widgetIds | index("aurelia.workspaces")) and
        (.clockEntryPoint | endswith("/plugins/aurelia.clock/ClockBarWidget.qml")) and
        .bluetoothSection == "right" and
        .hasNotifications == true and
        ([.summaries[] | select(.id == "aurelia.clock")][0].entryPoint | endswith("/plugins/aurelia.clock/ClockBarWidget.qml"))
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] dedicated bar registry projects current widgets, metadata, canonical entry points, and multi-kind notifications"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] BarWidgetRegistry fixture failed (status=$runtime_status): $details"
fi
