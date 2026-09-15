import QtQuick
import Quickshell.Hyprland
import "WindowRouting.js" as WindowRouting

// Workspace-first activation for application windows. A foreign toplevel
// activation request may be ignored while its workspace is hidden, so switch
// the workspace explicitly and wait for compositor state before requesting
// focus. This mirrors notification Open routing and keeps the retry budget
// deliberately finite.
QtObject {
    id: root

    property var pendingTarget: null
    property var pendingWorkspaceRoute: null
    property int workspaceRouteAttempts: 0
    readonly property int workspaceRouteMaxAttempts: 30
    property Timer workspaceRouteTimer: Timer {
        interval: 80
        repeat: false
        onTriggered: root.resolvePendingWorkspaceRoute()
    }

    function objectProperty(object, name) {
        try {
            return object && object[name] !== undefined && object[name] !== null ? object[name] : null
        } catch (error) {
            console.warn("[WINDOWS] property_read_failed name=" + String(name || ""))
            return null
        }
    }

    function workspaceId(workspace) {
        var id = Number(root.objectProperty(workspace, "id"))
        return isFinite(id) && Math.floor(id) === id && id !== 0 ? id : 0
    }

    function workspaceFocused(workspace) {
        if (!workspace) return false
        try {
            if (typeof workspace.focused === "boolean") return workspace.focused
        } catch (error) {
            // Fall back to the singleton's current workspace below.
            console.warn("[WINDOWS] workspace_state_read_failed")
        }
        var id = root.workspaceId(workspace)
        var focused = Hyprland.focusedWorkspace
        return id !== 0 && focused !== null && Number(focused.id) === id
    }

    function requestWorkspace(workspace) {
        if (!workspace) return false
        try {
            if (typeof workspace.activate === "function") {
                workspace.activate()
                return true
            }

            var id = root.workspaceId(workspace)
            if (id === 0) return false
            if (Hyprland.usingLua)
                Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + String(id) + "\" })")
            else Hyprland.dispatch("workspace " + String(id))
            return true
        } catch (error) {
            console.warn("[WINDOWS] workspace_activation_failed")
            return false
        }
    }

    function clearPending() {
        root.pendingTarget = null
        root.pendingWorkspaceRoute = null
        root.workspaceRouteAttempts = 0
        root.workspaceRouteTimer.stop()
    }

    function activate(target) {
        var handle = root.objectProperty(target, "handle")
        if (!target || !handle || typeof handle.activate !== "function") return "not-found"
        root.workspaceRouteTimer.stop()
        root.pendingTarget = target
        root.pendingWorkspaceRoute = null
        root.workspaceRouteAttempts = 0
        root.resolvePendingWorkspaceRoute()
        return "ok"
    }

    function start(route) {
        if (!route || !route.enabled) return "unavailable"
        root.workspaceRouteTimer.stop()
        root.pendingTarget = null
        root.pendingWorkspaceRoute = route
        root.workspaceRouteAttempts = 0
        root.resolvePendingWorkspaceRoute()
        return "ok"
    }

    function focusWorkspace(workspaceId) {
        var id = Number(workspaceId)
        if (!isFinite(id) || Math.floor(id) !== id || id === 0) return false
        var normalized = String(id)
        try {
            if (Hyprland.usingLua)
                Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + normalized + "\" })")
            else Hyprland.dispatch("workspace " + normalized)
            return true
        } catch (error) {
            console.warn("[WINDOWS] workspace_route_failed id=" + normalized)
            return false
        }
    }

    function resolvePendingWorkspaceRoute() {
        var route = root.pendingWorkspaceRoute
        var directTarget = root.pendingTarget
        if (!route && !directTarget) return

        var match = null
        if (directTarget) {
            var directWorkspace = root.objectProperty(directTarget, "workspace")
            var directWorkspaceId = root.workspaceId(directWorkspace)
            if (!directWorkspace || directWorkspaceId === 0) {
                try { directTarget.handle.activate() } catch (error) {
                    console.warn("[WINDOWS] direct_toplevel_activation_failed")
                }
                root.clearPending()
                return
            }
            match = {
                toplevel: directTarget,
                workspace: directWorkspace,
                workspaceId: directWorkspaceId,
                score: 0
            }
        } else {
            try { Hyprland.refreshToplevels() } catch (error) {
                console.warn("[WINDOWS] toplevel_refresh_failed")
            }
            var values = []
            try { values = Hyprland.toplevels ? Hyprland.toplevels.values || [] : [] } catch (valuesError) {
                console.warn("[WINDOWS] toplevel_values_read_failed")
            }
            match = WindowRouting.matchingWorkspaceToplevel(route, values)
        }

        if (match) {
            if (root.workspaceRouteAttempts >= root.workspaceRouteMaxAttempts) {
                console.info("[WINDOWS] workspace.route_unavailable")
                root.clearPending()
                return
            }

            var focusedWorkspace = Hyprland.focusedWorkspace
            var workspaceFocused = match.workspace && typeof match.workspace.focused === "boolean"
                ? match.workspace.focused
                : (!!focusedWorkspace && Number(focusedWorkspace.id) === match.workspaceId)
            if (!workspaceFocused) {
                console.info("[WINDOWS] workspace.switch_requested id=" + match.workspaceId)
                try {
                    if (match.workspace && typeof match.workspace.activate === "function") match.workspace.activate()
                    else root.focusWorkspace(match.workspaceId)
                    try { Hyprland.refreshWorkspaces() } catch (refreshError) {
                        console.warn("[WINDOWS] workspace_refresh_failed")
                    }
                } catch (error) {
                    console.warn("[WINDOWS] workspace_activation_exception")
                    root.focusWorkspace(match.workspaceId)
                }
                root.workspaceRouteAttempts++
                root.workspaceRouteTimer.interval = 80
                root.workspaceRouteTimer.restart()
                return
            }

            try {
                var handle = match.toplevel && match.toplevel.handle
                if (handle && typeof handle.activate === "function") handle.activate()
            } catch (error) {
                // The action remains successful even if the application closes
                // before its foreign toplevel can be activated.
                console.warn("[WINDOWS] toplevel_activation_exception")
            }

            try { Hyprland.refreshWorkspaces() } catch (refreshError) {
                console.warn("[WINDOWS] workspace_refresh_failed")
            }
            var focusedAfterActivation = Hyprland.focusedWorkspace
            if (!focusedAfterActivation || Number(focusedAfterActivation.id) !== match.workspaceId) {
                root.workspaceRouteAttempts++
                root.workspaceRouteTimer.interval = 80
                root.workspaceRouteTimer.restart()
                return
            }

            console.info("[WINDOWS] workspace.routed id=" + match.workspaceId +
                (match.score > 0 ? " score=" + match.score : ""))
            root.clearPending()
            return
        }

        if (root.workspaceRouteAttempts >= root.workspaceRouteMaxAttempts) {
            console.info("[WINDOWS] workspace.route_unavailable")
            root.clearPending()
            return
        }
        root.workspaceRouteAttempts++
        root.workspaceRouteTimer.restart()
    }
}
