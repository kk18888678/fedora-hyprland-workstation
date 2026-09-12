#!/usr/bin/env bash

# T20 bounded plugin-tree watcher and targeted/full reload checks.

set -Eeuo pipefail

section "Aurelia Plugin Watcher and Reload Policy"

services_root="$ROOT/services"
registry_root="$services_root/PluginRegistry.qml"
shell_root="$ROOT/shell.qml"
policy_root="$services_root/PluginWatcherPolicy.qml"

if [[ -f "$policy_root" ]] &&
   grep -q 'PluginWatcherPolicy' "$services_root/qmldir" &&
   grep -q 'watcherPolicy' "$registry_root" &&
   grep -q 'localPluginTreeChanged' "$registry_root" &&
   grep -q 'onLocalPluginTreeChanged' "$shell_root" &&
   grep -q 'localPluginWatcherFailureClass' "$registry_root" &&
   grep -q 'code !== 0' "$registry_root"; then
    pass "[static] watcher path mapping, full-tree fallback, and fail-closed watcher state are explicit"
else
    fail "[static] watcher policy or failure boundary is incomplete"
fi

if grep -q 'watchedExtensions' "$policy_root" &&
   grep -q 'qml' "$policy_root" && grep -q 'js' "$policy_root" &&
   grep -q 'json' "$policy_root" && grep -q 'lua' "$policy_root" &&
   grep -q 'conf' "$policy_root" &&
   grep -q 'firstPartyDir' "$registry_root" && grep -q 'userPluginsDir' "$registry_root" &&
   grep -q 'interval: 150' "$shell_root" &&
   ! grep -q 'watch.*Quickshell' "$registry_root"; then
    pass "[static] supported source/config files use the existing debounce without broad core watching"
else
    fail "[static] watcher scope, file matrix, or debounce policy is incomplete"
fi

if grep -q 'pluginHost.beginReload' "$shell_root" &&
   grep -q 'reloadingPluginIds' "$services_root/PluginHost.qml" &&
   grep -q 'syncScopedFacades' "$services_root/PluginHost.qml" &&
   grep -q 'keepsResident' "$services_root/PluginHost.qml" &&
   grep -q 'onLocalPluginTreeChanged' "$shell_root"; then
    pass "[static] targeted reload, resident-service retention, and full-rescan fallback share one host boundary"
else
    fail "[static] reload lifecycle ownership or retention boundary is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] watcher path-policy QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mkdir -p -- "$runtime_root/runtime" "$runtime_root/state" "$runtime_root/config" "$runtime_root/cache"
result_path="$runtime_root/result.json"
runtime_status=0
AURELIA_WATCHER_POLICY_SOURCE="$policy_root" \
AURELIA_WATCHER_POLICY_RESULT="$result_path" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-watcher/policy.qml" \
    >"$runtime_root/watcher.log" 2>&1 || runtime_status=$?
if [[ "$runtime_status" -eq 0 ]] && jq -e '
    .directQml == "aurelia.clock" and .directJs == "aurelia.clock" and
    .groupedJson == "" and .groupedLua == "" and
    .groupedConf == "aurelia.single" and .newUser == "acme.new" and
    .newFirstParty == "aurelia.new" and .newGrouped == "" and
    .hidden == false and .gitMetadata == false and .outside == false
  ' "$result_path" >/dev/null; then
    pass "[isolated-runtime] grouped/sibling, user, new, hidden, Git, and out-of-scope watcher paths resolve safely"
else
    details="$(tail -n 24 "$runtime_root/watcher.log" 2>/dev/null || true)"
    fail "[isolated-runtime] watcher policy fixture failed (status=$runtime_status): $details"
fi
