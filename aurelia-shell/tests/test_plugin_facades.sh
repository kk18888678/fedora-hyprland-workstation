#!/usr/bin/env bash

# T14 scoped third-party facade checks.

set -Eeuo pipefail

section "Aurelia Scoped Plugin Facades"

services_root="$ROOT/services"
host_root="$services_root/PluginHost.qml"
bar_root="$ROOT/plugins/aurelia.bar"
shell_root="$ROOT/shell.qml"

if [[ -f "$services_root/PluginRegistryApi.qml" &&
      -f "$services_root/PluginShellApi.qml" &&
      -f "$services_root/PluginBarApi.qml" &&
      -f "$services_root/PluginBarWidgetRegistryApi.qml" &&
      -f "$services_root/PluginAppLibraryApi.qml" ]] &&
   grep -q 'PluginRegistryApi 1.0 PluginRegistryApi.qml' "$services_root/qmldir" &&
   grep -q 'PluginShellApi 1.0 PluginShellApi.qml' "$services_root/qmldir" &&
   grep -q 'PluginBarApi 1.0 PluginBarApi.qml' "$services_root/qmldir" &&
   grep -q 'PluginBarWidgetRegistryApi 1.0 PluginBarWidgetRegistryApi.qml' "$services_root/qmldir" &&
   grep -q 'PluginAppLibraryApi 1.0 PluginAppLibraryApi.qml' "$services_root/qmldir"; then
    pass "[static] scoped facade QML types are declared in the services module"
else
    fail "[static] scoped facade type declarations are incomplete"
fi

if grep -q 'publicPluginManifest' "$host_root" &&
   grep -q 'scopedRegistryApiFor' "$host_root" &&
   grep -q 'scopedShellApiFor' "$host_root" &&
   grep -q 'scopedBarApiFor' "$host_root" &&
   grep -q 'scopedBarWidgetRegistryApiFor' "$host_root" &&
   grep -q 'scopedAppLibraryApiFor' "$host_root" &&
   grep -q 'pruneScopedFacades' "$host_root" &&
   grep -q 'syncScopedFacades' "$host_root"; then
    pass "[static] PluginHost owns detached facade construction, refresh, and revocation"
else
    fail "[static] PluginHost facade lifecycle boundary is incomplete"
fi

if grep -q 'configurePluginTarget' "$host_root" &&
   grep -q 'host.scopedShellApiFor' "$host_root" &&
   grep -q 'host.scopedRegistryApiFor' "$host_root" &&
   grep -q 'host.scopedBarApiFor' "$host_root" &&
   grep -q 'host.scopedBarWidgetRegistryApiFor' "$host_root" &&
   grep -q 'property var pluginHost' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'pluginManifest.__isFirstParty !== false' "$bar_root/BarWidgetSlot.qml" &&
   grep -q 'pluginHost: barRoot.pluginHost' "$bar_root/Bar.qml" &&
   grep -q 'registryApiComponent: pluginRegistryApiComponent' "$shell_root"; then
    pass "[static] third-party bar entries receive scoped host injection while first-party wiring remains explicit"
else
    fail "[static] third-party facade injection wiring is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    pass "[skipped:isolated-runtime] scoped facade QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root" 2>/dev/null || true' RETURN
runtime_result="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
AURELIA_PLUGIN_FACADE_RESULT="$runtime_result" \
AURELIA_PLUGIN_FACADE_HOST_SOURCE="$host_root" \
AURELIA_PLUGIN_FACADE_REGISTRY_SOURCE="$services_root/PluginRegistryApi.qml" \
AURELIA_PLUGIN_FACADE_SHELL_SOURCE="$services_root/PluginShellApi.qml" \
AURELIA_PLUGIN_FACADE_BAR_SOURCE="$services_root/PluginBarApi.qml" \
AURELIA_PLUGIN_FACADE_WIDGET_SOURCE="$services_root/PluginBarWidgetRegistryApi.qml" \
AURELIA_PLUGIN_FACADE_APP_SOURCE="$services_root/PluginAppLibraryApi.qml" \
AURELIA_PLUGIN_FACADE_SLOT_SOURCE="$ROOT/plugins/aurelia.bar/BarWidgetSlot.qml" \
AURELIA_PLUGIN_FACADE_WIDGET_ENTRY_SOURCE="$ROOT/tests/fixtures/plugin-facades/Widget.qml" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" \
XDG_STATE_HOME="$runtime_root/state" \
XDG_CONFIG_HOME="$runtime_root/config" \
XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 10s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-facades/shell.qml" \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$runtime_result" ]] &&
   jq -e '
        .publicManifestHasSource == false and
        .publicManifestHasPartyMarker == false and
        .publicManifestHasCapabilityStamp == false and
        .rawShellConfigHidden == true and
        .selfUpdate == true and
        .foreignUpdate == false and
        .selfSummon == true and
        .foreignSummon == false and
        (.selfEntryPoint | endswith("/plugin-facades/Widget.qml")) and
        .foreignEntryPoint == "" and
        .foreignRequest == false and
        .publicBarConfigDetached == true and
        .barScalarState == true and
        .barForeignRequest == false and
        .barOwnRequest == true and
        .barWidgetLoaded == true and
        .barWidgetShellFacade == true and
        .barWidgetRegistryFacade == true and
        .barWidgetPluginRegistryScoped == true and
        .barWidgetManifestSanitized == true and
        .barWidgetShellConfigHidden == true and
        .selfRowLabel == "Fixture" and
        .snapshotCategory == "Testing" and
        .revokedAfterDisable == true and
        .revokedAfterProfileChange == true and
        .shellFacadeCount == 0 and
        .registryFacadeCount == 0
    ' "$runtime_result" >/dev/null; then
    pass "[isolated-runtime] third-party manifest sanitization, self-only lifecycle/settings, detached snapshots, and facade revocation behave correctly"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$runtime_result" ]]; then details="$details result=$(tr '\n' ' ' <"$runtime_result")"; fi
    fail "[isolated-runtime] scoped facade fixture failed (status=$runtime_status): $details"
fi
