#!/usr/bin/env bash

# T09 generic lifecycle-routing checks.

set -Eeuo pipefail

section "Aurelia Generic Plugin Routing"

host_root="$ROOT/services/PluginHost.qml"
shell_root="$ROOT/shell.qml"

if grep -q 'property string defaultBarId' "$host_root" &&
   grep -q 'host.defaultBarId' "$host_root" &&
   ! grep -q 'aurelia.notifications' "$host_root" &&
   ! grep -q 'itemFor("aurelia.bar")' "$shell_root"; then
    pass "[static] generic host routing resolves the default/active bar through one seam without notification-specific branches"
else
    fail "[static] generic host routing still contains repeated plugin-specific assumptions"
fi

if grep -q 'target: "keybindings"' "$shell_root" &&
   grep -q 'target: "hotkeys"' "$shell_root" &&
   grep -q 'pluginHost.activeBar()' "$shell_root" &&
   ! grep -Eq 'aurelia\.notifications|id !== "aurelia\.bar"|instanceId !== "aurelia\.bar"' "$host_root"; then
    pass "[static] compatibility IPC aliases remain explicit thin adapters and generic kinds avoid ID branches"
else
    fail "[static] compatibility aliases or generic kind routing are not cleanly separated"
fi

if grep -q 'fixture.menu-widget' "$ROOT/tests/fixtures/plugin-lifecycle/shell.qml" &&
   grep -q 'fixture.multi' "$ROOT/tests/fixtures/plugin-lifecycle/shell.qml" &&
   grep -q 'test_plugin_lifecycle.sh' "$ROOT/tests/run.sh"; then
    pass "[static] the generic lifecycle fixture provides panel/service/menu/widget coverage without host feature branches"
else
    fail "[static] generic lifecycle fixture coverage is incomplete"
fi
