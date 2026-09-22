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
   "$ROOT/bin/aurelia-plugin" validate --first-party "$plugin_root" >/dev/null; then
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
   grep -q 'WorkspaceSelection.nextIndex(index, delta, ids.length)' "$switcher_qml" &&
   grep -q 'if (recenter !== false) root.keepSelectionVisible()' "$switcher_qml" &&
   grep -q 'WheelHandler {' "$switcher_qml" &&
   grep -q 'root.wheelAccumulator += event.angleDelta.y' "$switcher_qml" &&
   grep -q 'while (Math.abs(root.wheelAccumulator) >= 120)' "$switcher_qml" &&
   ! grep -q 'onHovered: root.selectWorkspace' "$switcher_qml" &&
   grep -q 'Hyprland.refreshMonitors' "$switcher_qml" &&
   grep -q 'ListView.StrictlyEnforceRange' "$switcher_qml" &&
   grep -q 'interactive: false' "$switcher_qml" &&
   grep -q 'currentIndex: -1' "$switcher_qml" &&
   grep -q 'workspaceListView.currentIndex = index' "$switcher_qml" &&
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
   grep -q 'signal hovered()' "$card_qml" &&
   grep -q 'onPositionChanged: root.hovered()' "$card_qml"; then
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

# ---------------------------------------------------------------------------
# Configurable "only workspaces in use" policy
# ---------------------------------------------------------------------------
selection_js="$plugin_root/WorkspaceSelection.js"
if [[ -f "$selection_js" ]] &&
   grep -q 'import "WorkspaceSelection.js" as WorkspaceSelection' "$switcher_qml" &&
   grep -q 'readonly property bool onlyWorkspacesInUse' "$switcher_qml" &&
   grep -q 'Theme.getPreference("aurelia.workspaces.only_in_use", true)' "$switcher_qml" &&
   grep -q 'WorkspaceSelection.workspaceIds(' "$switcher_qml" &&
   grep -q 'function workspaceIds()' "$switcher_qml"; then
    pass "workspace overview exposes a configurable in-use-only selection policy"
else
    fail "workspace overview does not expose the configurable in-use-only selection policy"
fi

if grep -q '\["aurelia.workspaces.only_in_use"\]' "$ROOT/core/preferences.lua" &&
   grep -A6 '\["aurelia.workspaces.only_in_use"\]' "$ROOT/core/preferences.lua" |
       grep -q 'default = true'; then
    pass "aurelia.workspaces.only_in_use is a registered boolean preference defaulting to true"
else
    fail "aurelia.workspaces.only_in_use preference is not registered with the safe default"
fi

if command -v node >/dev/null; then
    if node -e '
const S = require(process.argv[1]);
const ws = (id, n) => ({ id, toplevels: { values: new Array(n).fill({}) } });
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// "all" mode keeps the reviewed 1..5 baseline plus live workspace ids.
const all = S.workspaceIds(false, [ws(3, 2), ws(7, 1)], 7, [1, 2, 3, 4, 5]);
// "in use" mode keeps non-empty workspaces plus the focused (possibly empty) one.
const inUse = S.workspaceIds(true, [ws(3, 2), ws(4, 0), ws(7, 1)], 4);
// A focused empty workspace must stay reachable so the overlay is never empty.
const onlyFocus = S.workspaceIds(true, [], 1);
// Out-of-range workspace ids never leak into either mode.
const bounded = S.workspaceIds(true, [ws(0, 1), ws(11, 1), ws(2, 1)], 2);
// Cyclic navigation wraps in both modes: forward past the end returns to the
// start and backward past the start returns to the end.
const allCycle = all.map((_, i) => all[S.nextIndex(i, 1, all.length)]);
const inUseCycle = inUse.map((_, i) => inUse[S.nextIndex(i, -1, inUse.length)]);

const ok = eq(all, [1, 2, 3, 4, 5, 7]) &&
    eq(inUse, [3, 4, 7]) &&
    eq(onlyFocus, [1]) &&
    eq(bounded, [2]) &&
    eq(allCycle, [2, 3, 4, 5, 7, 1]) &&
    eq(inUseCycle, [7, 3, 4]) &&
    S.nextIndex(0, 1, 1) === 0 && S.nextIndex(0, 1, 0) === -1;
if (!ok) console.error(JSON.stringify({ all, inUse, onlyFocus, bounded, allCycle, inUseCycle }));
process.exit(ok ? 0 : 1);
' "$selection_js" >/dev/null; then
        pass "workspace selection returns all or in-use-only workspaces and cycles cyclically in both modes"
    else
        fail "workspace selection policy is wrong for the all/in-use modes"
    fi
else
    skip "workspace selection policy (node unavailable)"
fi
