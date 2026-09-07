#!/usr/bin/env bash

# Contract tests for the first Aurelia application launcher slice.

set -Eeuo pipefail

launcher_root="$ROOT/plugins/aurelia.launcher"

section "Application Launcher Plugin"

if [[ -f "$launcher_root/manifest.json" && -f "$launcher_root/LauncherPlugin.qml" && -f "$launcher_root/ui/LauncherPanel.qml" && -f "$launcher_root/ui/LauncherModel.qml" ]] &&
   jq -e '.schemaVersion == 1 and .id == "aurelia.launcher" and .icon == "system-search" and (.kinds == ["panel"]) and .entryPoints.panel == "LauncherPlugin.qml"' "$launcher_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$launcher_root" >/dev/null 2>&1; then
    pass "Application Launcher declares a validated first-party panel plugin"
else
    fail "Application Launcher manifest or entry points are incomplete"
fi

if grep -q 'workstation-keybindings' "$launcher_root/LauncherPlugin.qml" &&
   grep -q 'function reload()' "$launcher_root/ui/LauncherModel.qml" &&
   grep -q 'command = \["gtk-launch", desktopId\]' "$launcher_root/ui/LauncherModel.qml" &&
   grep -q 'target: "aurelia.launcher"' "$launcher_root/LauncherPlugin.qml" &&
   grep -q 'shell.summon("aurelia.launcher"' "$ROOT/plugins/aurelia.bar/AureliaLogo.qml"; then
    pass "Logo-to-launcher IPC and structured desktop application launch are separated from UI"
else
    fail "Application Launcher runtime boundary is incomplete"
fi

if grep -q 'filteredApplications' "$launcher_root/ui/LauncherModel.qml" &&
   grep -q 'Search applications' "$launcher_root/ui/LauncherPanel.qml" &&
   grep -q 'leftPadding: Theme.spacingMd' "$launcher_root/ui/LauncherPanel.qml" &&
   grep -q 'calculatedCardHeight' "$launcher_root/ui/LauncherPanel.qml" &&
   grep -q 'Key_Down' "$launcher_root/ui/LauncherPanel.qml" &&
   grep -q 'Key_Return' "$launcher_root/ui/LauncherPanel.qml" &&
   ! grep -Eq '(^|[[:space:];])eval([[:space:];]|$)' "$launcher_root/ui/LauncherModel.qml"; then
    pass "Launcher provides keyboard-first filtering and no shell eval path"
else
    fail "Application Launcher keyboard or safety contract is incomplete"
fi
