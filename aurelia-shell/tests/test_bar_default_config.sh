#!/usr/bin/env bash

# T23 canonical default bar source and generic registration checks.

set -Eeuo pipefail

section "Aurelia Canonical Bar Defaults"

default_file="$ROOT/config/bar-default.json"
default_service="$ROOT/services/BarDefaultConfig.qml"
shell_config="$ROOT/services/ShellConfig.qml"
bar_root="$ROOT/plugins/aurelia.bar/Bar.qml"

if [[ -f "$default_file" && -f "$default_service" ]] &&
   grep -q 'BarDefaultConfig 1.0 BarDefaultConfig.qml' "$ROOT/services/qmldir" &&
   grep -q 'property BarDefaultConfig barDefaults' "$shell_config" &&
   grep -q 'barDefaults.copy' "$shell_config" &&
   grep -q 'shellConfig.defaultBarConfig' "$bar_root" &&
   jq -e '.id == "aurelia.bar" and .position == "top" and .centerAnchor == "aurelia.clock" and
          (.layout.left[0].id == "aurelia.workspaces") and
          ([.layout.center[].id] == ["aurelia.notifications", "aurelia.clock", "aurelia.weather"]) and
          ([.layout.right[].id] == ["aurelia.tray", "aurelia.network", "aurelia.bluetooth", "aurelia.monitor", "aurelia.screenshot", "aurelia.power"])' \
       "$default_file" >/dev/null; then
    pass "[static] one canonical repository bar-default document feeds ShellConfig and Bar with a recovery fallback"
else
    fail "[static] canonical bar-default source wiring is incomplete"
fi

if ! grep -q 'aurelia.notifications' "$bar_root" &&
   ! grep -q 'aurelia.weather' "$bar_root" &&
   ! grep -q 'aurelia.tray' "$bar_root" &&
   ! grep -q 'aurelia.notifications' "$shell_config" &&
   grep -q 'pluginRegistry.pluginIds' "$ROOT/services/BarWidgetRegistry.qml" &&
   ! grep -q 'aurelia.notifications' "$ROOT/services/BarWidgetRegistry.qml"; then
    pass "[static] duplicated widget defaults and hardcoded generic widget registration are absent"
else
    fail "[static] duplicate default layout or generic host registration remains"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] canonical bar-default QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config" "$runtime_root/cache"
result_path="$runtime_root/result.json"
runtime_status=0
AURELIA_BAR_DEFAULT_SOURCE="$default_service" \
AURELIA_BAR_DEFAULT_RESULT="$result_path" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/bar-default/shell.qml" \
    >"$runtime_root/default.log" 2>&1 || runtime_status=$?
if [[ "$runtime_status" -eq 0 ]] && jq -e '
    .loaded == true and .id == "aurelia.bar" and .position == "top" and
    .centerAnchor == "aurelia.clock" and
    .left == ["aurelia.workspaces"] and
    .center == ["aurelia.notifications", "aurelia.clock", "aurelia.weather"] and
    .right == ["aurelia.tray", "aurelia.network", "aurelia.bluetooth", "aurelia.monitor", "aurelia.screenshot", "aurelia.power"]
  ' "$result_path" >/dev/null; then
    pass "[isolated-runtime] canonical bar-default loader returns the preserved default layout"
else
    details="$(tail -n 24 "$runtime_root/default.log" 2>/dev/null || true)"
    fail "[isolated-runtime] canonical bar-default fixture failed (status=$runtime_status): $details"
fi
