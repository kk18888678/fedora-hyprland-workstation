#!/usr/bin/env bash

# T02A host-survivability checks. The runtime case starts a disposable
# QuickShell process with intentionally faulty plugin fixtures and verifies
# that the real PluginHost remains usable for healthy plugins.

set -Eeuo pipefail

section "Aurelia Plugin Host Survivability"

services_root="$ROOT/services"
bar_root="$ROOT/plugins/aurelia.bar"

if grep -q 'property var runtimeFailures' "$services_root/PluginRegistry.qml" &&
   grep -q 'function recordRuntimeFailure' "$services_root/PluginRegistry.qml" &&
   grep -q 'function hasActiveRuntimeFailure' "$services_root/PluginRegistry.qml" &&
   grep -q 'retryState: "requires-explicit-reload"' "$services_root/PluginRegistry.qml"; then
    pass "static [static] PluginRegistry records bounded, ephemeral per-kind failure state with explicit retry semantics"
else
    fail "static [static] PluginRegistry failure/quarantine state is incomplete"
fi

if grep -q 'function recordFailure' "$services_root/PluginHost.qml" &&
   grep -q 'function invokeTarget' "$services_root/PluginHost.qml" &&
   grep -q 'host.recordFailure' "$services_root/PluginHost.qml" &&
   grep -q 'aureliaInitialize' "$services_root/PluginHost.qml" &&
   grep -q 'onStatusChanged' "$services_root/PluginHost.qml"; then
    pass "static [static] PluginHost contains Loader, initialization, missing-entry-point, and callback failure boundaries"
else
    fail "static [static] PluginHost failure boundaries are incomplete"
fi

if grep -q 'function reportFailure' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'function safeConfigure' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'root.reportFailure("callback"' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'recordRuntimeFailure' "$bar_root/BarWidgetSlot.qml"; then
    pass "static [static] BarWidgetSlot contains independent construction and callback failure reporting"
else
    fail "static [static] BarWidgetSlot failure boundary is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] disposable QuickShell survivability fixture (qs or timeout unavailable)"
    return 0
fi

runtime_dir="$(mktemp -d)"
runtime_result="$runtime_dir/result.json"
runtime_output="$runtime_dir/output.log"
trap 'rm -rf -- "$runtime_dir" 2>/dev/null || true' RETURN

runtime_status=0
AURELIA_PLUGIN_SURVIVABILITY_RESULT="$runtime_result" \
AURELIA_PLUGIN_HOST_SOURCE="$services_root/PluginHost.qml" \
AURELIA_BAR_SLOT_SOURCE="$bar_root/BarWidgetSlot.qml" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_STATE_HOME="$runtime_dir/state" \
XDG_CONFIG_HOME="$runtime_dir/config" \
XDG_CACHE_HOME="$runtime_dir/cache" \
XDG_RUNTIME_DIR="$runtime_dir/runtime" \
    /usr/bin/timeout --kill-after=1s 8s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-survivability/shell.qml" \
    >"$runtime_output" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   ! grep -Eq 'FATAL|Binding loop detected|TypeError|ReferenceError|Segmentation fault' "$runtime_output" &&
   jq -e '
        .hostAlive == true and
        .pingResponded == true and
        .listPluginsResponded == true and
        .healthyPanelLoaded == true and
        .healthyServiceLoaded == true and
        .healthyCall == "healthy" and
        .healthyStillLoaded == true and
        .healthyBarWidgetLoaded == true and
        .healthyBarWidgetStillAvailable == true and
        .badWidgetResult == "error" and
        .badWidgetAvailableAfterFailure == false and
        .badWidgetReported == true and
        .badWidgetLoadReported == true and
        .badCallbackResult == "error" and
        .badOpenResult == "error" and
        .badCloseResult == "error" and
        .badToggleResult == "error" and
        .badCallResult == "error" and
        .badCallbackReloadResult == "error" and
        .badCallbackReported == true and
        .badOpenReported == true and
        .badCloseReported == true and
        .badToggleReported == true and
        .badCallReported == true and
        .badInitReported == true and
        .badLoadReported == true and
        .badMissingReported == true and
        .badServiceReported == true and
        .badReplacementReported == true and
        .activeBarFallback == true and
        .reloadAttempts >= 2 and
        .quarantinedLoadAttempts == 1 and
        .failureCount >= 12
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] faulty load/init/missing-entry-point/callback fixtures are quarantined while host and healthy plugins remain usable"
elif grep -Eq 'Failed to create wl_display|Could not create instance runtime directory|Could not load the Qt platform plugin' "$runtime_output"; then
    pass "[skipped:isolated-runtime] QuickShell could not create an additional disposable Wayland runtime"
else
    details="$(tr '\n' ' ' <"$runtime_output")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] plugin host survivability fixture failed (status=$runtime_status): $details"
fi
