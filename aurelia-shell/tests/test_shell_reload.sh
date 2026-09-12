#!/usr/bin/env bash

# Contract tests for the Omarchy-inspired Aurelia development reload boundary.
# Plugin entry points may reload in-place; the resident host itself remains an
# explicit restart boundary.

set -Eeuo pipefail

section "Aurelia Shell Development Reload"

registry_root="$ROOT/services/PluginRegistry.qml"
host_root="$ROOT/services/PluginHost.qml"
shell_root="$ROOT/shell.qml"
launcher_root="$ROOT/plugins/aurelia.launcher"

if grep -q 'signal localPluginChanged(string pluginId)' "$registry_root" &&
   grep -q 'hotReloadEnabled' "$registry_root" &&
   grep -q 'inotifywait' "$registry_root" &&
   grep -q 'localPluginWatcherRestart' "$registry_root"; then
    pass "development mode watches local plugin trees with a bounded restart delay"
else
    fail "development plugin watcher contract is incomplete"
fi

if grep -q 'property bool reloading: false' "$host_root" &&
   grep -q 'property var reloadingPluginIds: null' "$host_root" &&
   grep -q 'function beginReload(pluginIds)' "$host_root" &&
   grep -q 'function finishReload()' "$host_root" &&
   grep -q 'property string defaultBarId' "$host_root" &&
   grep -q '!host.keepsResident' "$host_root" &&
   grep -q 'instanceId === host.defaultBarId' "$host_root" &&
   grep -q 'reloadingPluginIds\[instanceId\]' "$host_root"; then
    pass "PluginHost keeps the default bar and keepLoaded owners mounted while scoping Loader reloads to changed ids"
else
    fail "PluginHost targeted reload or resident-bar lifecycle is incomplete"
fi

if grep -q 'function reloadPlugins()' "$shell_root" &&
   grep -q 'typeof Qt.clearComponentCache === "function"' "$shell_root" &&
   grep -q 'function queuePluginReload(pluginId)' "$shell_root" &&
   grep -q 'pendingPluginReloadIds' "$shell_root" &&
   grep -q 'onLocalPluginChanged' "$shell_root" &&
   grep -q 'return root.reloadPlugins()' "$shell_root"; then
    pass "shell IPC and the local watcher share a debounced targeted reload path"
else
    fail "shell plugin reload path is incomplete"
fi

if grep -q 'property bool reloading: false' "$ROOT/plugins/aurelia.bar/BarWidgetSlot.qml" &&
   grep -q 'onLocalPluginChanged' "$ROOT/plugins/aurelia.bar/BarWidgetSlot.qml" &&
   grep -q 'function reloadWidgets()' "$ROOT/plugins/aurelia.bar/Bar.qml"; then
    pass "bar widgets reload independently while the resident bar surface remains mapped"
else
    fail "bar widget isolation from the resident bar host is incomplete"
fi

if grep -q 'watchChanges: true' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'onFileChanged: configRoot.reload()' "$ROOT/services/ShellConfig.qml" &&
   grep -q 'QS_DISABLE_FILE_WATCHER=1' "$ROOT/bin/aurelia-launch-shell"; then
    pass "shell.json watches in place while broad Quickshell file watching stays disabled"
else
    fail "configuration or Quickshell watcher ownership is incomplete"
fi

if jq -e '[.modules[] | select(.id == "aurelia-shell" and .enabled == true and .implemented == true)] | length == 1' \
    "$launcher_root/modules.json" >/dev/null &&
   grep -q 'id: "aurelia-shell"' "$launcher_root/ui/CommandCenterModuleRegistry.qml" &&
   grep -q 'kind: "shell-action"' "$launcher_root/ui/CommandCenterModel.qml" &&
   grep -q 'Quickshell.execDetached' "$launcher_root/ui/CommandCenterModel.qml"; then
    pass "Command Center exposes plugin reload and detached resident-shell restart actions"
else
    fail "Command Center Aurelia Shell actions are incomplete"
fi

if grep -q 'shellClientBin' "$launcher_root/CommandCenterPlugin.qml" &&
   grep -q 'shellRestartBin' "$launcher_root/CommandCenterPlugin.qml" &&
   grep -q 'shellClientBin: panelRoot.shellClientBin' "$launcher_root/ui/CommandCenterPanel.qml" &&
   grep -q 'shellRestartBin: panelRoot.shellRestartBin' "$launcher_root/ui/CommandCenterPanel.qml" &&
   grep -q '\[root.shellClientBin, "shell", "rescanPlugins"\]' "$launcher_root/ui/CommandCenterModel.qml"; then
    pass "Command Center receives absolute injected Aurelia helpers and uses structured argv"
else
    fail "Command Center Aurelia helper injection or IPC argv is incomplete"
fi

if grep -q 'inotify-tools' "$ROOT/../packages/aurelia.txt" &&
   grep -q 'quickshell' "$ROOT/../packages/aurelia.txt" &&
   ! grep -q 'inotify-tools' "$ROOT/../packages/desktop.txt"; then
    pass "Aurelia package manifest owns the runtime and development watcher dependencies"
else
    fail "Aurelia package manifest does not own its runtime/development dependencies"
fi
