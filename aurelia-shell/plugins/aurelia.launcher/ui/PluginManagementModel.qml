import QtQuick
import Quickshell
import Quickshell.Io

import "../../../services/AureliaAppSearch.js" as Search

// Read-only plugin management rows plus a structured argv action runner. The
// Command Center owns presentation; the lifecycle CLI remains the one mutation
// owner for plugin trees and shell state.
QtObject {
    id: root

    property var pluginRegistry: null
    property var pluginHost: null
    property string pluginCliBin: ""
    property var pluginItems: []
    property bool busy: false
    property string lastAction: ""
    property string lastPluginId: ""
    property string statusMessage: ""
    property string errorMessage: ""

    signal actionFinished(bool success, string message)

    function cloneJson(value) {
        try {
            return JSON.parse(JSON.stringify(value))
        } catch (error) {
            return null
        }
    }

    function catalogSnapshot() {
        var catalog = null
        if (root.pluginHost && typeof root.pluginHost.catalog === "function") catalog = root.pluginHost.catalog()
        else if (root.pluginRegistry && typeof root.pluginRegistry.pluginCatalog === "function") catalog = root.pluginRegistry.pluginCatalog()
        if (!catalog || !Array.isArray(catalog.plugins)) return []
        return root.cloneJson(catalog.plugins) || []
    }

    function hasCloneFor(items, sourceId) {
        for (var i = 0; i < items.length; i++) {
            if (items[i] && items[i].firstParty !== true && String(items[i].clonedFrom || "") === String(sourceId || ""))
                return true
        }
        return false
    }

    function statusText(item) {
        var values = [item.enabled === true ? "Enabled" : "Disabled", item.source || "unknown"]
        if (item.active === true) values.push("Active")
        if (item.inBar === true) values.push("In bar")
        if (item.errorState) values.push("Error")
        return values.join(" · ")
    }

    function appendAction(rows, item, action, order) {
        var name = String(item.name || item.id)
        var labels = {
            enable: "Enable ",
            disable: "Disable ",
            clone: "Clone ",
            remove: "Remove ",
            update: "Update ",
            validate: "Validate "
        }
        var details = String(item.id || "") + " · " + (Array.isArray(item.kinds) ? item.kinds.join(", ") : "plugin")
        if (item.clonedFrom) details += " · clone of " + item.clonedFrom
        if (item.errorState && item.errorState.detail) details += " · " + item.errorState.detail
        rows.push({
            id: "plugin-action:" + action + ":" + item.id,
            kind: "plugin-action",
            moduleId: "plugins",
            pluginAction: action,
            pluginId: String(item.id || ""),
            label: labels[action] + name,
            subtitle: statusText(item),
            detail: details,
            icon: String(item.icon || "system-run"),
            pluginSourceRoot: String(item.sourceRoot || ""),
            pluginManifestPath: String(item.manifestPath || ""),
            pluginFirstParty: item.firstParty === true,
            order: order,
            keywords: [action, name, item.id, item.source, item.kind, item.clonedFrom || ""].join(" ")
        })
    }

    function buildRows(items, queryValue) {
        var rows = []
        for (var i = 0; i < items.length; i++) {
            var item = items[i]
            if (!item || typeof item.id !== "string") continue
            var baseOrder = i * 100
            if (item.enabled !== true) appendAction(rows, item, "enable", baseOrder + 10)
            else if (item.canDisable !== false) appendAction(rows, item, "disable", baseOrder + 10)

            if (item.firstParty === true && !item.clonedFrom && !root.hasCloneFor(items, item.id))
                appendAction(rows, item, "clone", baseOrder + 20)
            if (item.firstParty !== true) {
                appendAction(rows, item, "update", baseOrder + 30)
                appendAction(rows, item, "remove", baseOrder + 40)
            }
            appendAction(rows, item, "validate", baseOrder + 50)
        }
        return Search.sortRows(rows, queryValue)
    }

    function refresh() {
        root.pluginItems = root.catalogSnapshot()
        root.statusMessage = ""
        root.errorMessage = ""
    }

    function pluginRows(queryValue) {
        return root.buildRows(root.pluginItems, queryValue)
    }

    function open() {
        root.refresh()
    }

    function activate(row) {
        if (root.busy || !row || row.kind !== "plugin-action") return false
        var action = String(row.pluginAction || "")
        var pluginId = String(row.pluginId || "")
        if (["enable", "disable", "clone", "remove", "update", "validate"].indexOf(action) === -1 ||
            !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(pluginId)) {
            root.errorMessage = "Invalid plugin management action."
            root.actionFinished(false, root.errorMessage)
            return false
        }
        if (!root.pluginCliBin) {
            root.errorMessage = "Aurelia plugin CLI is unavailable."
            root.actionFinished(false, root.errorMessage)
            return false
        }
        var command = [root.pluginCliBin, action]
        if (action === "validate") {
            var sourceRoot = String(row.pluginSourceRoot || "")
            var manifestPath = String(row.pluginManifestPath || "")
            if (sourceRoot.charAt(0) !== "/" || sourceRoot === "/") {
                root.errorMessage = "Plugin source path is unavailable."
                root.actionFinished(false, root.errorMessage)
                return false
            }
            if (row.pluginFirstParty === true) command.push("--first-party")
            if (manifestPath !== "" && manifestPath.substring(manifestPath.lastIndexOf("/") + 1) !== "manifest.json")
                command.push("--manifest-file", manifestPath.substring(manifestPath.lastIndexOf("/") + 1))
            command.push(sourceRoot)
        } else {
            command.push(pluginId)
        }
        // The UI selection is the explicit user action; these flags make the
        // non-TTY child process obey the lifecycle CLI's confirmation boundary.
        if (action === "clone") command.push("--edit")
        if (action === "remove" || action === "update") command.push("--yes")
        root.lastAction = action
        root.lastPluginId = pluginId
        root.statusMessage = labelsForAction(action) + "..."
        root.errorMessage = ""
        root.busy = true
        actionProcess.command = command
        actionProcess.running = true
        return true
    }

    function labelsForAction(action) {
        var labels = {enable: "Enabling", disable: "Disabling", clone: "Cloning", remove: "Removing", update: "Updating", validate: "Validating"}
        return labels[action] || "Updating plugin"
    }

    property Process actionProcess: Process {
        id: actionProcess
        command: []
        stdout: StdioCollector { id: actionStdout }
        stderr: StdioCollector { id: actionStderr }

        onExited: function(code) {
            root.busy = false
            if (code === 0) {
                root.refresh()
                root.statusMessage = actionStdout.text.trim() || (root.lastAction + " completed.")
                root.actionFinished(true, "")
            } else {
                var message = actionStderr.text.trim() || actionStdout.text.trim() || "Plugin management action failed."
                root.errorMessage = message
                root.statusMessage = ""
                root.actionFinished(false, message)
            }
        }
    }

    property Connections registryConnection: Connections {
        target: root.pluginRegistry
        function onPluginsChanged() { root.refresh() }
    }
}
