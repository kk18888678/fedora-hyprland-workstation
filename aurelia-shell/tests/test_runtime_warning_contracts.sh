#!/usr/bin/env bash

# T29 warning-stream and component-construction regression checks.

set -Eeuo pipefail

section "Aurelia Runtime Warning Contracts"

launcher_root="$ROOT/plugins/aurelia.launcher"
display_root="$ROOT/plugins/aurelia.monitor"
network_root="$ROOT/plugins/aurelia.network"
bluetooth_root="$ROOT/plugins/aurelia.bluetooth"
menu_root="$ROOT/plugins/aurelia.menu"
wifiqr_root="$ROOT/plugins/aurelia.wifiqr"

if grep -q 'property var pluginManagement: null' "$launcher_root/ui/CommandCenterPanel.qml" &&
   grep -q 'pluginManagement: pluginManagement' "$launcher_root/CommandCenterPlugin.qml"; then
    pass "[static] Command Center panel declares the injected plugin-management model"
else
    fail "[static] Command Center plugin-management property contract is incomplete"
fi

if grep -q 'onBackendRootChanged: root.refresh()' "$display_root/DisplayPanel.qml" &&
   ! grep -q 'onBackendRootChanged: Qt.callLater' "$display_root/DisplayPanel.qml" &&
   ! grep -q 'if (!active) Qt.callLater' "$ROOT/services/PluginHost.qml"; then
    pass "[static] DisplayPanel refreshes synchronously and cannot retain a stale delayed callback"
else
    fail "[static] DisplayPanel stale-refresh callback guard is incomplete"
fi

if grep -q 'readonly property bool ipcOwner' "$network_root/NetworkBarWidget.qml" &&
   grep -q 'property bool ipcReady' "$network_root/NetworkBarWidget.qml" &&
   grep -q 'active: root.ipcOwner && root.ipcReady' "$network_root/NetworkBarWidget.qml" &&
   grep -q 'readonly property bool ipcOwner' "$bluetooth_root/BluetoothBarWidget.qml" &&
   grep -q 'property bool ipcReady' "$bluetooth_root/BluetoothBarWidget.qml" &&
   grep -q 'active: root.ipcOwner && root.ipcReady' "$bluetooth_root/BluetoothBarWidget.qml" &&
   grep -q 'widgetRevision' "$network_root/NetworkBarWidget.qml" &&
   grep -q 'widgetRevision' "$bluetooth_root/BluetoothBarWidget.qml"; then
    pass "[static] network and Bluetooth IPC handlers are scoped to one active bar-slot owner"
else
    fail "[static] bar-widget IPC ownership guard is incomplete"
fi

if grep -q '"introspect"' "$bluetooth_root/BluetoothBarWidget.qml" &&
   grep -q '"org.freedesktop.DBus.ObjectManager"' "$bluetooth_root/BluetoothBarWidget.qml" &&
   grep -q 'function hasBluezService(output)' "$bluetooth_root/BluetoothBarWidget.qml" &&
   grep -q '^import "\."$' "$network_root/NetworkPanel.qml"; then
    pass "[static] Bluetooth probes the object-manager capability before native QML construction"
else
    fail "[static] BlueZ object-manager construction guard is incomplete"
fi

if grep -Fq 'import Quickshell.Io' "$menu_root/Menu.qml" &&
   grep -Fq 'IpcHandler' "$menu_root/Menu.qml" &&
   grep -Fq 'import Quickshell.Io' "$wifiqr_root/WifiQrPlugin.qml" &&
   grep -Fq 'IpcHandler' "$wifiqr_root/WifiQrPlugin.qml"; then
    pass "[static] Menu and Wi-Fi QR entry points import the module that owns their IPC type"
else
    fail "[static] Menu or Wi-Fi QR entry point has an unresolved IPC type import"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] warning-stream QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

warning_root="$(mktemp -d)"
trap 'rm -rf -- "$warning_root"  || true' RETURN
warning_result="$warning_root/result.json"
warning_log="$warning_root/runtime.log"
warning_status=0
mkdir -p -- "$warning_root/home" "$warning_root/config" "$warning_root/state" "$warning_root/cache"
: >"$warning_result"
HOME="$warning_root/home" \
XDG_CONFIG_HOME="$warning_root/config" \
XDG_STATE_HOME="$warning_root/state" \
XDG_CACHE_HOME="$warning_root/cache" \
XDG_RUNTIME_DIR="$warning_root/runtime" \
AURELIA_SHELL_ROOT="$ROOT" \
AURELIA_WARNING_LAUNCHER_SOURCE="file://$launcher_root/CommandCenterPlugin.qml" \
AURELIA_WARNING_DISPLAY_SOURCE="file://$display_root/DisplayPanel.qml" \
AURELIA_WARNING_NETWORK_SOURCE="file://$network_root/NetworkBarWidget.qml" \
AURELIA_WARNING_BLUETOOTH_SOURCE="file://$bluetooth_root/BluetoothBarWidget.qml" \
AURELIA_WARNING_MENU_SOURCE="file://$menu_root/Menu.qml" \
AURELIA_WARNING_WIFIQR_SOURCE="file://$wifiqr_root/WifiQrPlugin.qml" \
AURELIA_WARNING_DISPLAY_BACKEND="$warning_root/backend" \
AURELIA_WARNING_RESULT="$warning_result" \
QT_QPA_PLATFORM=offscreen \
WAYLAND_DISPLAY="" \
    /usr/bin/timeout --kill-after=1s 12s /usr/bin/qs --no-duplicate \
    --path "$ROOT/tests/fixtures/plugin-warning-smoke/shell.qml" \
    >"$warning_log" 2>&1 || warning_status=$?

if [[ "$warning_status" -eq 0 ]] &&
   jq -e '
       .initialNetworkAOwner == true and
       .initialNetworkBOwner == false and
       .initialBluetoothAOwner == true and
       .initialBluetoothBOwner == false and
       .finalNetworkAOwner == false and
       .finalNetworkBOwner == true and
       .finalBluetoothAOwner == false and
       .finalBluetoothBOwner == true and
       .bluezObjectManagerProbe == true and
       .menuLoaded == true and
       .wifiQrLoaded == true and
       .bluezInvalidProbe == true
   ' "$warning_result" >/dev/null &&
   runtime_log_is_environment_only "$warning_log"; then
    pass "[isolated-runtime] affected components load without the reported construction, stale-refresh, duplicate-handler, or BlueZ object-manager warnings"
elif runtime_log_has_environment_diagnostic "$warning_log" &&
     runtime_skip_if_environment_only "$warning_log" "[isolated-runtime] warning-stream fixture could not create an additional QuickShell surface"; then
    :
else
    details="$(tail -n 48 "$warning_log"  || true)"
    if [[ -s "$warning_result" ]]; then details="$details result=$(tr '\n' ' ' <"$warning_result")"; fi
    fail "[isolated-runtime] warning-stream fixture failed (status=$warning_status): $details"
fi
