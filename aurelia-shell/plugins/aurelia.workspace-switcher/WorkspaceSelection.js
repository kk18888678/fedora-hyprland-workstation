// WorkspaceSelection.js — pure workspace-selection policy for the Mission
// Control overview.
//
// The switcher supports two modes, selected by the user preference
// `aurelia.workspaces.only_in_use`:
//
//   * "all":       the historical behaviour — a 1..5 baseline plus every live
//                  workspace id in 1..10.
//   * "in use":    only workspaces that currently hold windows. The focused
//                  workspace is always kept reachable so the overlay can never
//                  open with nothing to select while the user is on an empty
//                  workspace.
//
// Keeping the policy here (instead of inside the QML overlay) lets both modes
// and the cyclic-navigation wrap be unit tested without a running compositor.

function workspaceId(value) {
    var id = Number(value)
    if (!isFinite(id) || Math.floor(id) !== id || id < 1 || id > 10) return 0
    return id
}

function hasWindows(workspace) {
    if (!workspace || !workspace.toplevels || !workspace.toplevels.values) return false
    return workspace.toplevels.values.length > 0
}

// All workspaces: the reviewed 1..5 baseline plus any live workspace in 1..10.
function allWorkspaceIds(workspaces, baseline) {
    var ids = (baseline || [1, 2, 3, 4, 5]).slice()
    var values = workspaces || []
    for (var i = 0; i < values.length; i++) {
        var id = workspaceId(values[i] && values[i].id)
        if (id !== 0 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(left, right) { return left - right })
    return ids
}

// Only workspaces that are actually in use (have windows), plus the focused
// workspace so an empty current workspace remains selectable.
function inUseWorkspaceIds(workspaces, focusedId) {
    var ids = []
    var values = workspaces || []
    for (var i = 0; i < values.length; i++) {
        var id = workspaceId(values[i] && values[i].id)
        if (id === 0 || !hasWindows(values[i])) continue
        if (ids.indexOf(id) === -1) ids.push(id)
    }
    var focus = workspaceId(focusedId)
    if (focus !== 0 && ids.indexOf(focus) === -1) ids.push(focus)
    ids.sort(function(left, right) { return left - right })
    return ids
}

// Dispatch between the two modes. `onlyInUse` is the effective user
// preference; the default is true (in-use only).
function workspaceIds(onlyInUse, workspaces, focusedId, baseline) {
    return onlyInUse
        ? inUseWorkspaceIds(workspaces, focusedId)
        : allWorkspaceIds(workspaces, baseline)
}

// Next index for cyclic navigation. Returns -1 when there is nothing to
// cycle. A single entry resolves to itself, preserving wrap-around.
function nextIndex(currentIndex, delta, count) {
    if (!count || count <= 0) return -1
    var step = Number(delta) < 0 ? -1 : 1
    var index = Number(currentIndex)
    if (!isFinite(index) || index < 0 || index >= count) index = 0
    return ((index + step) % count + count) % count
}

// Alt+Tab-style commit-on-modifier-release decision. Returns the workspace id
// a modifier release should activate, or 0 when the release must be ignored
// (the overview is closed, the selection is malformed, or the selected
// workspace left the navigable set while the overview was open). Keeping this
// pure lets the release-commit path be unit tested without a compositor, just
// like the cycle wrap above.
function releaseCommitWorkspace(isOpen, selectedWorkspaceId, workspaceIds) {
    if (isOpen !== true) return 0
    var selected = workspaceId(selectedWorkspaceId)
    if (selected === 0) return 0
    var ids = workspaceIds || []
    for (var i = 0; i < ids.length; i++) {
        if (workspaceId(ids[i]) === selected) return selected
    }
    return 0
}

var AureliaWorkspaceSelection = {
    workspaceId: workspaceId,
    hasWindows: hasWindows,
    allWorkspaceIds: allWorkspaceIds,
    inUseWorkspaceIds: inUseWorkspaceIds,
    workspaceIds: workspaceIds,
    nextIndex: nextIndex,
    releaseCommitWorkspace: releaseCommitWorkspace
}

if (typeof module !== "undefined" && module.exports) module.exports = AureliaWorkspaceSelection
