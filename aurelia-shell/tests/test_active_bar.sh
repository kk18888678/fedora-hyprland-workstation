#!/usr/bin/env bash

# T08 active replacement-bar parity checks.

set -Eeuo pipefail

section "Aurelia Active Replacement Bar"

host_root="$ROOT/services/PluginHost.qml"
bar_root="$ROOT/plugins/aurelia.bar"

if grep -q 'readonly property string selectedBarId' "$host_root" &&
   grep -q 'readonly property string activeBarId' "$host_root" &&
   grep -q 'failedBarId' "$host_root" &&
   grep -q 'id !== host.activeBarId' "$host_root"; then
    pass "[static] active bar selection has a validated fallback and one active Loader"
else
    fail "[static] active bar selector or fallback boundary is incomplete"
fi

if grep -q 'function activeBar()' "$host_root" &&
   grep -q 'pluginHost.activeBar()' "$ROOT/shell.qml" &&
   grep -q 'barWidgetRegistry' "$bar_root/Bar.qml"; then
    pass "[static] active full-bar ownership remains separate from bar-widget registration"
else
    fail "[static] active-bar/widget ownership boundary is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] active-bar QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
AURELIA_BAR_SELECTION_HOST_SOURCE="$host_root" \
AURELIA_BAR_SELECTION_RESULT="$runtime_result" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-selection/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e '
        .hostAlive == true and
        .pingResponded == true and
        .initialBuiltIn == true and
        .replacementSuccess == true and
        .brokenFallback == true and
        .disabledFallback == true and
        .rescanSuccess == true and
        .activeBarId == "replacement.bar" and
        .fullBarCount == 1 and
        .builtInLoaded == false and
        .replacementLoaded == true and
        .brokenReported == true
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] built-in/replacement success, failure fallback, disable fallback, rescan, and exactly-one-bar invariants pass"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] active-bar fixture failed (status=$runtime_status): $details"
fi
