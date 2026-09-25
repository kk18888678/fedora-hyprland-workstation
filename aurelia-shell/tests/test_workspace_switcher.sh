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
   grep -q 'runnable = true' "$binding_lua" &&
   grep -q 'release_commit = {' "$binding_lua" &&
   grep -q 'modifier = "SUPER"' "$binding_lua" &&
   grep -q '"shell", "call", "aurelia.workspace-switcher", "release"' "$binding_lua"; then
    pass "SUPER+TAB is owned by the workspace overview through provider-registered plugin IPC"
else
    fail "SUPER+TAB workspace overview binding is incomplete"
fi

# Alt+Tab-style commit-on-modifier-release is established in the Hyprland Lua
# provider, not as a declarative `release = true` bind. A `SUPER + TAB` release
# bind would fire on TAB release (committing mid-cycle), so the provider instead
# observes the input.keyboard.key event and forwards a bounded plugin IPC.
provider_lua="$ROOT/dotfiles/hypr/keybind.lua"
if [[ -f "$provider_lua" ]] &&
   grep -q 'MODIFIER_XKB_KEYCODES' "$provider_lua" &&
   grep -q '\[133\] = true, \[134\] = true' "$provider_lua" &&
   grep -q 'hl.on("input.keyboard.key"' "$provider_lua" &&
   grep -q 'state ~= 0' "$provider_lua" &&
   grep -q 'armed_release_commit' "$provider_lua" &&
   grep -q 'function release_commit_for(item)' "$provider_lua" &&
   grep -q 'register_release_commit()' "$provider_lua" &&
   grep -q 'release_commit has an unsupported modifier' "$provider_lua" &&
   grep -q 'bindr' "$provider_lua"; then
    pass "provider observes the SUPER release through input.keyboard.key and gates a bounded plugin IPC"
else
    fail "commit-on-release provider mechanism is missing or uses a declarative release bind"
fi

if grep -q 'function release()' "$switcher_qml" &&
   grep -q 'WorkspaceSelection.releaseCommitWorkspace(' "$switcher_qml" &&
   grep -q 'return root.activateWorkspace(id)' "$switcher_qml"; then
    pass "workspace overview exposes a release commit that converges on activateWorkspace"
else
    fail "workspace overview release commit path is incomplete"
fi

# Quick-tap (fast ALT+TAB) interaction contract. The overlay opens without
# revealing, the timer defers the reveal, navigation reveals immediately, and
# both the resident surface visibility and keyboard focus are gated on the
# revealed flag so a tap never renders the overlay.
if grep -q 'property int activeWorkspaceId: 0' "$switcher_qml" &&
   grep -q 'property int previousWorkspaceId: 0' "$switcher_qml" &&
   grep -q 'property bool interactionRevealed: false' "$switcher_qml" &&
   grep -q 'property bool interactionNavigated: false' "$switcher_qml" &&
   grep -q 'function knownWorkspaceIds()' "$switcher_qml" &&
   grep -q 'function recordFocusedWorkspace()' "$switcher_qml" &&
   grep -q 'function toggleToPrevious()' "$switcher_qml" &&
   grep -q 'function revealInteraction()' "$switcher_qml" &&
   grep -q 'function noteInteraction()' "$switcher_qml" &&
   grep -q 'WorkspaceSelection.toggleTarget(' "$switcher_qml" &&
   grep -q 'WorkspaceSelection.isQuickTap(root.isOpen, root.interactionRevealed, root.interactionNavigated)' "$switcher_qml" &&
   grep -q 'id: revealTimer' "$switcher_qml" &&
   grep -q 'interval: WorkspaceSelection.TAP_HOLD_THRESHOLD_MS' "$switcher_qml" &&
   grep -q 'onTriggered: root.revealInteraction()' "$switcher_qml" &&
   grep -q 'visible: root.isOpen && root.interactionRevealed' "$switcher_qml" &&
   grep -q 'WlrLayershell.keyboardFocus: (root.isOpen && root.interactionRevealed)' "$switcher_qml" &&
   grep -q 'Component.onCompleted: root.recordFocusedWorkspace()' "$switcher_qml" &&
   grep -q 'revealTimer.stop()' "$switcher_qml" &&
   grep -q 'revealTimer.restart()' "$switcher_qml"; then
    pass "quick tap defers the overlay reveal and gates visibility/focus on the revealed flag"
else
    fail "quick-tap interaction contract is incomplete"
fi

# The pair must be swapped before activation, otherwise the asynchronous
# Hyprland focus signal would overwrite the previous workspace while a rapid
# second tap is still in flight.
toggle_swap_line="$(grep -n 'root.previousWorkspaceId = root.activeWorkspaceId' "$switcher_qml" | head -1 | cut -d: -f1)"
toggle_activate_line="$(grep -n 'return root.activateWorkspace(target)' "$switcher_qml" | head -1 | cut -d: -f1)"
if [[ -n "$toggle_swap_line" && -n "$toggle_activate_line" && "$toggle_swap_line" -lt "$toggle_activate_line" ]]; then
    pass "quick-tap pair swap happens before activation to avoid the async focus race"
else
    fail "quick-tap pair swap ordering is wrong"
fi

# open() must not re-read the focused workspace into the pair: a rapid second
# tap depends on the optimistic swap in toggleToPrevious(), and a focus signal
# that has not arrived yet would clobber it.
if awk '/function open\(payloadJson\)/{inside=1} inside && /^    \}/{inside=0} inside && /root\.recordFocusedWorkspace\(\)/{found=1} END{exit found?1:0}' "$switcher_qml"; then
    pass "open() does not clobber the optimistic quick-tap swap"
else
    fail "open() re-seeds the focus pair and can clobber a rapid second tap"
fi

if grep -q 'event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space' "$switcher_qml" &&
   grep -q 'root.activateWorkspace(root.selectedWorkspaceId)' "$switcher_qml"; then
    pass "Enter activation is retained alongside the new release commit"
else
    fail "Enter activation path was removed or altered"
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
   grep -q 'function workspaceIds()' "$switcher_qml" &&
   grep -q 'function releaseCommitWorkspace(isOpen, selectedWorkspaceId, workspaceIds)' "$selection_js"; then
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

    if node -e '
const S = require(process.argv[1]);
// A release while open commits the selected navigable workspace.
// A release while closed, a malformed selection, or a workspace that left the
// navigable set is ignored so an unrelated SUPER release cannot activate.
const ok = S.releaseCommitWorkspace(true, 3, [1, 3, 5]) === 3 &&
    S.releaseCommitWorkspace(true, "4", [4]) === 4 &&
    S.releaseCommitWorkspace(false, 3, [1, 3, 5]) === 0 &&
    S.releaseCommitWorkspace(true, 7, [1, 3, 5]) === 0 &&
    S.releaseCommitWorkspace(true, 0, [1, 3, 5]) === 0 &&
    S.releaseCommitWorkspace(true, 2, []) === 0 &&
    S.releaseCommitWorkspace(true, 11, [11]) === 0 &&
    S.releaseCommitWorkspace(true, NaN, [1]) === 0;
process.exit(ok ? 0 : 1);
' "$selection_js" >/dev/null; then
        pass "release commit activates only an open, still-navigable selection"
    else
        fail "release commit decision is wrong for the closed/stale selection cases"
    fi

    if node -e '
const S = require(process.argv[1]);
// The hold threshold is pinned. It must be a positive number so the deferred
// reveal is bounded; the QML timer mirrors this exact value.
const ok = S.TAP_HOLD_THRESHOLD_MS === 180 && typeof S.TAP_HOLD_THRESHOLD_MS === "number";
process.exit(ok ? 0 : 1);
' "$selection_js" >/dev/null; then
        pass "quick-tap hold threshold is pinned at 180 ms"
    else
        fail "quick-tap hold threshold is not the pinned 180 ms"
    fi

    if node -e '
const S = require(process.argv[1]);
// A tap targets the previous workspace only when it is a known, still-live
// workspace different from the active one; everything else falls back to 0 so
// the caller keeps the normal commit path.
const known = [1, 2, 3, 4, 5, 7];
const ok = S.toggleTarget(3, 5, known) === 3 &&
    S.toggleTarget("3", "5", known) === 3 &&
    S.toggleTarget(0, 5, known) === 0 &&
    S.toggleTarget(5, 5, known) === 0 &&
    S.toggleTarget(9, 5, known) === 0 &&
    S.toggleTarget(3, 5, []) === 0 &&
    S.toggleTarget(11, 5, [11]) === 0 &&
    S.toggleTarget(null, 5, known) === 0 &&
    S.toggleTarget(NaN, 5, known) === 0;
process.exit(ok ? 0 : 1);
' "$selection_js" >/dev/null; then
        pass "quick tap targets only a known, non-active previous workspace"
    else
        fail "quick tap target decision is wrong"
    fi

    if node -e '
const S = require(process.argv[1]);
// A quick tap is exactly an open interaction that was never revealed and never
// navigated; any other combination keeps commit-on-release behaviour.
const ok = S.isQuickTap(true, false, false) === true &&
    S.isQuickTap(true, true, false) === false &&
    S.isQuickTap(true, false, true) === false &&
    S.isQuickTap(true, true, true) === false &&
    S.isQuickTap(false, false, false) === false &&
    S.isQuickTap(true, undefined, undefined) === true &&
    S.isQuickTap(1, 0, 0) === false;
process.exit(ok ? 0 : 1);
' "$selection_js" >/dev/null; then
        pass "quick-tap decision requires an open, unrevealed, unnavigated interaction"
    else
        fail "quick-tap decision is wrong"
    fi
else
    skip "workspace selection policy (node unavailable)"
fi

# Exercise the provider release wiring with a mocked `hl` surface. This proves
# the gated press arms the SUPER release companion, that unrelated releases are
# ignored, that the companion fires exactly once, and that a malformed
# companion declaration falls back to the plain press binding.
if command -v luajit >/dev/null; then
    lua_fixture="$(mktemp -d)"
    cat >"$lua_fixture/release_provider_test.lua" <<'LUA'
local keybind_path = os.getenv("KEYBIND_LUA")
assert(keybind_path and keybind_path ~= "", "KEYBIND_LUA missing")

local registered = {}
local listeners = {}
local executed = {}

hl = {
    bind = function(keys, dispatcher, opts)
        registered[keys] = registered[keys] or {}
        table.insert(registered[keys], { dispatcher = dispatcher, opts = opts or {} })
        return { remove = function() end }
    end,
    on = function(event, callback)
        listeners[event] = callback
        return { remove = function() end }
    end,
    exec_cmd = function(command)
        table.insert(executed, tostring(command))
    end,
}
local function dsp_proxy(name)
    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, key) return dsp_proxy(name .. "." .. key) end,
        __call = function(_, ...) return { mock = name } end,
    })
    return proxy
end
hl.dsp = dsp_proxy("dsp")

local function mock_bindings(entries)
    package.loaded["keybindings_manifest"] = { mainMod = "SUPER" }
    package.loaded["effective_bindings"] = {
        resolve_bindings = function()
            return { mainMod = "SUPER", bindings = entries }
        end,
    }
end

mock_bindings({
    {
        id = "aurelia.workspace_switcher.toggle",
        key = "SUPER + TAB",
        action_type = "plugin_ipc",
        command_argv = { "/bin/true", "toggle" },
        release_commit = {
            modifier = "SUPER",
            command_argv = { "/bin/true", "release" },
        },
    },
})

local chunk, err = loadfile(keybind_path)
assert(chunk, "keybind.lua failed to load: " .. tostring(err))
local ok, run_err = pcall(chunk)
assert(ok, "keybind.lua failed to run: " .. tostring(run_err))

local press = registered["SUPER + TAB"]
assert(press and #press == 1, "SUPER + TAB press binding not registered")
local release = listeners["input.keyboard.key"]
assert(type(release) == "function", "input.keyboard.key listener not registered")
assert(type(press[1].dispatcher) == "function", "gated press dispatcher must arm through a Lua function")

-- An unrelated release before any press must not dispatch anything.
release(133, 1000, 0)
assert(#executed == 0, "release without an armed interaction dispatched something")

-- A non-SUPER release while armed must not dispatch the release companion.
press[1].dispatcher()
assert(#executed == 1 and executed[1]:find("toggle", 1, true), "press did not dispatch toggle")
release(30, 1001, 0)
assert(#executed == 1, "non-SUPER release dispatched the release companion")

-- A pressed state must not dispatch the release companion.
release(133, 1002, 1)
assert(#executed == 1, "pressed state dispatched the release companion")

-- The SUPER release commits once and disarms.
release(133, 1003, 0)
assert(#executed == 2, "SUPER release did not dispatch the release companion")
assert(executed[2]:find("release", 1, true), "release companion command is wrong")
release(134, 1004, 0)
assert(#executed == 2, "release companion dispatched more than once")

-- Re-arming with another cycle then releasing commits again.
press[1].dispatcher()
release(134, 1005, 0)
assert(#executed == 4 and executed[4]:find("release", 1, true), "re-armed release did not commit")

-- A malformed companion falls back to the plain press binding.
registered = {}
listeners = {}
executed = {}
mock_bindings({
    {
        id = "bad.modifier",
        key = "SUPER + F5",
        action_type = "plugin_ipc",
        command_argv = { "/bin/true", "toggle" },
        release_commit = { modifier = "HYPER", command_argv = { "/bin/true", "release" } },
    },
})
local bad_chunk = assert(loadfile(keybind_path))
assert(pcall(bad_chunk))
local bad = registered["SUPER + F5"]
assert(bad and type(bad[1].dispatcher) ~= "function", "malformed companion must keep the plain dispatcher")

print("release provider ok")
LUA
    if KEYBIND_LUA="$provider_lua" luajit "$lua_fixture/release_provider_test.lua" >/dev/null; then
        pass "provider arms and dispatches the SUPER release companion exactly once"
    else
        fail "provider release wiring does not arm, gate, or dispatch correctly"
    fi
    rm -rf -- "$lua_fixture"
else
    skip "provider release wiring (luajit unavailable)"
fi
