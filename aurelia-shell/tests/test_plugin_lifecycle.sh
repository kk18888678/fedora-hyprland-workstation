#!/usr/bin/env bash

# T07 resident and multi-kind lifecycle checks.

set -Eeuo pipefail

section "Aurelia Plugin Lifecycle Semantics"

host_root="$ROOT/services/PluginHost.qml"
fixture_root="$ROOT/tests/fixtures/plugin-lifecycle"

if grep -q 'function keepsResident' "$host_root" &&
   grep -q '!host.keepsResident' "$host_root" &&
   grep -q 'Array.isArray(pending)' "$host_root" &&
   grep -q 'queue.push' "$host_root"; then
    pass "[static] resident reload retention and ordered pending-open queues are explicit"
else
    fail "[static] keepLoaded or pending-open lifecycle semantics are incomplete"
fi

if grep -q 'kinds: \["service", "bar-widget"\]' "$fixture_root/shell.qml" &&
   grep -q 'barWidget: "MultiWidget.qml"' "$fixture_root/shell.qml" &&
   grep -q 'fixture.menu-widget' "$fixture_root/shell.qml" &&
   grep -q 'pluginReloaded' "$host_root"; then
    pass "[static] service+widget and menu+widget fixtures exercise separate kind owners"
else
    fail "[static] multi-kind lifecycle fixture is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] lifecycle QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
AURELIA_LIFECYCLE_HOST_SOURCE="$ROOT/services/PluginHost.qml" \
AURELIA_LIFECYCLE_BAR_REGISTRY_SOURCE="$ROOT/services/BarWidgetRegistry.qml" \
AURELIA_LIFECYCLE_RESULT="$runtime_result" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 9s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e '
        .hostAlive == true and
        .pingResponded == true and
        .residentPreserved == true and
        .keptPreserved == true and
        .multiServicePreserved == true and
        .multiWidgetRegistered == true and
        .menuWidgetRegistered == true and
        .menuLoaded == true and
        .queueFirstResult == "pending" and
        .queueSecondResult == "pending" and
        .queuePayloadsInOrder == true and
        .toggleResult == "ok" and
        .closeResult == "ok" and
        .lazyUnloaded == true and
        .loadedEventAvailable == true and
        .reloadEventAvailable == true
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] resident services/kept panels survive reload, multi-kind owners remain distinct, payloads preserve order, and lazy plugins unload"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] lifecycle fixture failed (status=$runtime_status): $details"
fi
