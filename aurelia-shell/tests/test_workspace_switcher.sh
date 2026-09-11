#!/usr/bin/env bash

# Contract checks for the Mission Control-style workspace overview plugin.

set -Eeuo pipefail

plugin_root="$ROOT/plugins/aurelia.workspace-switcher"
switcher_qml="$plugin_root/WorkspaceSwitcher.qml"
card_qml="$plugin_root/WorkspaceCard.qml"
preview_qml="$plugin_root/WindowPreview.qml"
binding_lua="$plugin_root/keybindings.lua"

section "Workspace Overview Plugin"

if [[ -f "$plugin_root/manifest.json" && -f "$switcher_qml" && -f "$card_qml" && -f "$preview_qml" ]] &&
   jq -e '
       .schemaVersion == 1 and
       .id == "aurelia.workspace-switcher" and
       .name == "Workspace Overview" and
       (.kinds == ["overlay"]) and
       .keepLoaded == true and
       .entryPoints.overlay == "WorkspaceSwitcher.qml"
   ' "$plugin_root/manifest.json" >/dev/null &&
   "$ROOT/bin/aurelia-plugin" validate --first-party "$plugin_root" >/dev/null 2>&1; then
    pass "workspace overview is a validated resident overlay plugin"
else
    fail "workspace overview manifest or entry-point contract is incomplete"
fi

if grep -q 'Quickshell.Hyprland' "$switcher_qml" &&
   grep -q 'Quickshell.Wayland' "$switcher_qml" &&
   ! grep -q 'IpcHandler {' "$switcher_qml" &&
   grep -q 'WlrLayer.Overlay' "$switcher_qml" &&
   grep -q 'WlrKeyboardFocus.Exclusive' "$switcher_qml" &&
   grep -q 'anchors.fill: parent' "$switcher_qml" &&
   grep -q 'anchors.centerIn: parent' "$switcher_qml" &&
   grep -q 'opacity: 0.95' "$switcher_qml" &&
   grep -q 'function workspaceIds()' "$switcher_qml" &&
   grep -q 'function workspaceById(id)' "$switcher_qml" &&
   grep -q 'function detectedFocusedWorkspaceId()' "$switcher_qml" &&
   grep -q 'activeWorkspace = monitor ? monitor.activeWorkspace : null' "$switcher_qml" &&
   grep -q 'values\[i\].focused === true' "$switcher_qml" &&
   grep -q 'function onFocusedWorkspaceChanged()' "$switcher_qml" &&
   grep -q 'function activateWorkspace(id)' "$switcher_qml" &&
   grep -q 'if (root.isOpen) return root.cycle(1)' "$switcher_qml" &&
   grep -q 'Math.max(0, Math.min(ids.length - 1, index + step))' "$switcher_qml" &&
   grep -q 'return "edge"' "$switcher_qml" &&
   grep -q 'Hyprland.refreshMonitors' "$switcher_qml" &&
   grep -q 'ListView.StrictlyEnforceRange' "$switcher_qml" &&
   grep -q 'positionViewAtIndex(index, ListView.Center)' "$switcher_qml" &&
   grep -q 'id: workspaceInputShield' "$switcher_qml" &&
   grep -q 'onClicked: function(mouse) { mouse.accepted = true }' "$switcher_qml" &&
   grep -q 'Hyprland.refreshToplevels' "$switcher_qml" &&
   grep -q 'property var workspaceEntry' "$switcher_qml" &&
   grep -q 'focused: root.currentWorkspaceId === modelData' "$switcher_qml" &&
   grep -q 'WorkspaceCard {' "$switcher_qml"; then
    pass "overview derives workspace state from Hyprland and keeps activation in the plugin controller"
else
    fail "workspace overview state or native activation boundary is incomplete"
fi

if grep -q 'ScreencopyView {' "$preview_qml" &&
   grep -q 'captureSource: root.active ? root.captureToplevel : null' "$preview_qml" &&
   grep -q 'ToplevelManager.toplevels' "$preview_qml" &&
   grep -q 'function onValuesChanged()' "$preview_qml" &&
   grep -q 'live: false' "$preview_qml" &&
   grep -q 'captureView.captureFrame' "$preview_qml" &&
   grep -q 'captureRetry' "$preview_qml" &&
   grep -q 'sourceAspectRatio' "$preview_qml" &&
   grep -q 'anchors.centerIn: parent' "$preview_qml" &&
   grep -q 'DesktopEntries.heuristicLookup' "$preview_qml" &&
   grep -q 'visible: !captureView.visible' "$preview_qml"; then
    pass "window previews use bounded single-frame toplevel capture with an app/title fallback"
else
    fail "window preview capture, fallback, or resource-boundary contract is incomplete"
fi

if grep -q 'GridLayout {' "$card_qml" &&
   grep -q 'root.windowCount' "$card_qml" &&
   grep -q 'readonly property var previewWindows' "$card_qml" &&
   grep -q 'i < values.length && i < 4' "$card_qml" &&
   grep -q 'text: "Empty"' "$card_qml" &&
   grep -q 'id: workspaceBadge' "$card_qml" &&
   grep -q 'id: selectionRing' "$card_qml" &&
   grep -q 'border.width: 2' "$card_qml" &&
   grep -q 'onPressed: function(mouse) { mouse.accepted = true }' "$card_qml" &&
   grep -q 'text: root.selected' "$card_qml" &&
   grep -q '"Selected"' "$card_qml" &&
   grep -q 'visible: root.selected' "$card_qml" &&
   grep -q 'signal activated()' "$card_qml" &&
   grep -q 'signal hovered()' "$card_qml"; then
    pass "workspace cards show bounded window tiles, empty-state affordances, and predictable hit targets"
else
    fail "workspace card layout or interaction contract is incomplete"
fi

if [[ -f "$binding_lua" ]] &&
   grep -q 'id = "aurelia.workspace_switcher.toggle"' "$binding_lua" &&
   grep -q 'key = "SUPER + TAB"' "$binding_lua" &&
   grep -q 'action_type = "plugin_ipc"' "$binding_lua" &&
   grep -q 'target = "aurelia.workspace-switcher"' "$binding_lua" &&
   grep -q 'method = "toggle"' "$binding_lua" &&
   grep -q '"shell", "call", "aurelia.workspace-switcher", "toggle"' "$binding_lua" &&
   grep -q 'runnable = true' "$binding_lua"; then
    pass "SUPER+TAB is owned by the workspace overview through provider-registered plugin IPC"
else
    fail "SUPER+TAB workspace overview binding is incomplete"
fi

binding_fixture="$(mktemp -d)"
binding_json=""
if binding_json="$(
    KEYBINDINGS_MANIFEST="$ROOT/dotfiles/hypr/keybindings_manifest.lua" \
    KEYBINDINGS_OVERRIDES="$binding_fixture/missing-overrides.json" \
    KEYBINDINGS_USER_ACTIONS="$binding_fixture/missing-actions.json" \
    XDG_CONFIG_HOME="$binding_fixture/config" \
    "$ROOT/bin/aurelia-shell-keybindings" json
)" &&
   jq -e 'any(.[]; .id == "aurelia.workspace_switcher.toggle" and .key == "SUPER + TAB" and .action_type == "plugin_ipc" and .runnable == true)' <<<"$binding_json" >/dev/null; then
    pass "plugin binding is merged into the effective keybinding projection"
else
    fail "effective keybinding projection does not contain the workspace overview action"
fi
rm -rf -- "$binding_fixture"
