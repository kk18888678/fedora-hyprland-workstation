#!/usr/bin/env bash

# T19 catalog discoverability and Aurelia Command Center management checks.

set -Eeuo pipefail

section "Aurelia Plugin Discoverability and Management"

services_root="$ROOT/services"
launcher_root="$ROOT/plugins/aurelia.launcher"
model_root="$launcher_root/ui/PluginManagementModel.qml"

if [[ -f "$services_root/PluginCatalogProjection.qml" && -f "$model_root" ]] &&
   grep -q 'active:' "$services_root/PluginCatalogProjection.qml" &&
   grep -q 'inBar:' "$services_root/PluginCatalogProjection.qml" &&
   grep -q 'canDisable:' "$services_root/PluginCatalogProjection.qml" &&
   grep -q 'errorState:' "$services_root/PluginCatalogProjection.qml" &&
   grep -q 'kind:' "$services_root/PluginCatalogProjection.qml" &&
   grep -q 'plugin-action' "$model_root" &&
   grep -q 'actionProcess' "$model_root" &&
   grep -q 'pluginHost.catalog' "$model_root" &&
   grep -q 'aurelia_plugin_list' "$ROOT/bin/lib/aurelia-plugin/main.sh"; then
    pass "[static] canonical catalog rows and the detached Command Center management model expose plugin state"
else
    fail "[static] catalog projection or management model is incomplete"
fi

if grep -q 'id: "plugins"' "$launcher_root/ui/CommandCenterModuleRegistry.qml" &&
   jq -e '.modules[] | select(.id == "plugins" and .implemented == true and .enabled == true)' \
       "$launcher_root/modules.json" >/dev/null &&
   grep -q 'pluginManagement: pluginManagement' "$launcher_root/CommandCenterPlugin.qml" &&
   grep -q 'pluginCliBin' "$launcher_root/CommandCenterPlugin.qml" &&
   grep -q 'row.kind === "plugin-action"' "$launcher_root/ui/CommandCenterModel.qml" &&
   grep -q 'validate' "$model_root"; then
    pass "[static] Plugins is an additive Command Center module with enable/disable/clone/update/remove/validate actions"
else
    fail "[static] Command Center plugin management module wiring is incomplete"
fi

list_root="$(mktemp -d)"
mkdir -p -- "$list_root/bin" "$list_root/home" "$list_root/plugins"
cp -- "$ROOT/tests/fixtures/plugin-management/list-shell" "$list_root/aurelia-shell"
chmod 0755 "$list_root/aurelia-shell"
list_json="$(PATH="$list_root:$PATH" HOME="$list_root/home" AURELIA_PLUGIN_DIR="$list_root/plugins" \
    AURELIA_PLUGIN_BIN_DIR="$list_root" AURELIA_DEVELOPMENT_MODE=1 \
    bash -c 'source "$1/common.sh"; source "$1/main.sh"; aurelia_plugin_main list --json' \
    _ "$ROOT/bin/lib/aurelia-plugin")"
list_human="$(PATH="$list_root:$PATH" HOME="$list_root/home" AURELIA_PLUGIN_DIR="$list_root/plugins" \
    AURELIA_PLUGIN_BIN_DIR="$list_root" AURELIA_DEVELOPMENT_MODE=1 \
    bash -c 'source "$1/common.sh"; source "$1/main.sh"; aurelia_plugin_main list' \
    _ "$ROOT/bin/lib/aurelia-plugin")"
if jq -e 'length == 2 and .[1].clonedFrom == "aurelia.clock" and .[1].errorState.detail == "fixture failure"' \
       <<<"$list_json" >/dev/null &&
   grep -q 'ID.*SOURCE.*KIND.*IN-BAR.*CLONE-OF.*ERROR' <<<"$list_human" &&
   grep -q $'tester.clock\tuser\tbar-widget\tyes\tno\tno\tno\tyes\tyes\taurelia.clock\tfixture failure' <<<"$list_human"; then
    pass "[isolated-runtime] list provides the complete JSON projection and a human-readable state table"
else
    fail "[isolated-runtime] plugin list projection or formatting is incomplete"
fi
rm -rf -- "$list_root"

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] catalog projection and management model QuickShell fixtures (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
mkdir -p -- "$runtime_root/empty-shell/bin" "$runtime_root/catalog/runtime" \
    "$runtime_root/catalog/state" "$runtime_root/catalog/config" "$runtime_root/catalog/cache"
catalog_result="$runtime_root/catalog/result.json"
catalog_status=0
# The fixture is copied into the temporary tree so its source directory does
# not participate in the empty first-party scan above.
cp -- "$ROOT/tests/fixtures/plugin-management/catalog.qml" "$runtime_root/catalog.qml"
catalog_status=0
AURELIA_PLUGIN_CATALOG_REGISTRY_SOURCE="$services_root/PluginRegistry.qml" \
AURELIA_PLUGIN_CATALOG_RESULT="$catalog_result" \
AURELIA_SHELL_ROOT="$runtime_root/empty-shell" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/catalog/runtime" XDG_STATE_HOME="$runtime_root/catalog/state" \
XDG_CONFIG_HOME="$runtime_root/catalog/config" XDG_CACHE_HOME="$runtime_root/catalog/cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$runtime_root/catalog.qml" >"$runtime_root/catalog/catalog.log" 2>&1 || catalog_status=$?
if [[ "$catalog_status" -eq 0 ]] && jq -e '
    .barActive and
    .source.source == "first-party" and .source.kind == "bar-widget" and .source.canDisable == true and
    .clone.source == "user" and .clone.kind == "bar-widget" and .clone.enabled == true and
    .clone.inBar == true and .clone.clonedFrom == "aurelia.clock" and
    .clone.errorDetail == "fixture failure" and .rejected == 0
  ' "$catalog_result" >/dev/null; then
    pass "[isolated-runtime] canonical catalog projection reports source, kind, active, enablement, bar, clone, and error state"
else
    details="$(tail -n 24 "$runtime_root/catalog/catalog.log" 2>/dev/null || true)"
    fail "[isolated-runtime] catalog projection fixture failed (status=$catalog_status): $details"
fi

mkdir -p -- "$runtime_root/management/runtime" "$runtime_root/management/state" \
    "$runtime_root/management/config" "$runtime_root/management/cache" "$runtime_root/management/bin"
cp -- "$ROOT/tests/fixtures/plugin-management/fake-cli" "$runtime_root/management/bin/aurelia-plugin"
chmod 0755 "$runtime_root/management/bin/aurelia-plugin"
management_result="$runtime_root/management/result.json"
management_calls="$runtime_root/management/calls"
touch "$management_calls"
management_status=0
AURELIA_PLUGIN_MANAGEMENT_MODEL_SOURCE="$ROOT/plugins/aurelia.launcher/ui/PluginManagementModel.qml" \
AURELIA_PLUGIN_MANAGEMENT_CLI="$runtime_root/management/bin/aurelia-plugin" \
AURELIA_PLUGIN_MANAGEMENT_RESULT="$management_result" \
AURELIA_PLUGIN_MANAGEMENT_CALLS="$management_calls" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/management/runtime" XDG_STATE_HOME="$runtime_root/management/state" \
XDG_CONFIG_HOME="$runtime_root/management/config" XDG_CACHE_HOME="$runtime_root/management/cache" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-management/management.qml" \
    >"$runtime_root/management/management.log" 2>&1 || management_status=$?
if [[ "$management_status" -eq 0 ]] && jq -e '
    .success and .action == "remove" and .pluginId == "tester.weather" and
    .hasEnable and .hasUpdate and .hasRemove and .hasValidate and .hasClone and .hasDisable
  ' "$management_result" >/dev/null &&
   grep -qx 'remove tester.weather --yes' "$management_calls"; then
    pass "[isolated-runtime] Command Center management rows invoke the safe CLI through structured argv"
else
    details="$(tail -n 24 "$runtime_root/management/management.log" 2>/dev/null || true)"
    fail "[isolated-runtime] management model fixture failed (status=$management_status): $details"
fi
