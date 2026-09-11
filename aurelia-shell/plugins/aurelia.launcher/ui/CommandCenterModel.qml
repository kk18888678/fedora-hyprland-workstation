import QtQuick
import Quickshell
import Quickshell.Io

import "../../../services/AureliaAppSearch.js" as Search
import "Calculator.js" as Calculator

// Command Center state and provider orchestration.
//
// The model owns only normalized rows and lifecycle. Applications are
// discovered by the shared native library; execution is delegated to the
// backend; pure calculator parsing lives in Calculator.js; file discovery is
// bounded by the backend. This keeps providers replaceable without growing a
// single QML process into a command interpreter.
QtObject {
    id: root

    property string backendBin: ""
    property string updatesBin: ""
    property string aboutBin: ""
    property string packagesBin: ""
    property string shellClientBin: ""
    property string shellRestartBin: ""
    property var processEnvironment: ({})
    property var appLibrary: null
    property var moduleRegistry: null

    property var actionItems: []
    property var fileItems: []
    property var results: []
    property string query: ""
    property string activeModule: ""
    property int selectedIndex: 0
    property string selectedId: ""
    property bool actionsLoaded: false
    property bool actionsLoading: false
    property bool filesLoading: false
    property string requestedFileQuery: ""
    property string fileQuery: ""
    property string pendingFileQuery: ""
    property string activeLaunchLabel: ""
    property string errorMessage: ""
    property string statusMessage: ""

    readonly property bool loading: actionsLoading || filesLoading
    readonly property string activeModuleName: {
        if (!root.activeModule || !root.moduleRegistry) return "Command Center"
        var module = root.moduleRegistry.moduleFor(root.activeModule)
        return module ? String(module.name || "Command Center") : "Command Center"
    }

    signal launchFinished(bool success, string message)

    function moduleEnabled(id) {
        return root.moduleRegistry && root.moduleRegistry.isEnabled(id)
    }

    function openUpdates() {
        if (!root.updatesBin) {
            root.errorMessage = "Updates backend is unavailable."
            return false
        }
        root.activeLaunchLabel = "Updates"
        root.statusMessage = "Opening update workflow..."
        launchProcess.command = [root.updatesBin, "open"]
        launchProcess.running = true
        return true
    }

    function openAbout() {
        if (!root.aboutBin) {
            root.errorMessage = "About backend is unavailable."
            return false
        }
        root.activeLaunchLabel = "About"
        root.statusMessage = "Opening Aurelia system details..."
        launchProcess.command = [root.aboutBin, "open"]
        launchProcess.running = true
        return true
    }

    function openPackageManager() {
        if (!root.packagesBin) {
            root.errorMessage = "Package Manager backend is unavailable."
            return false
        }
        root.activeLaunchLabel = "Package Manager"
        root.statusMessage = ""
        launchProcess.command = [root.packagesBin, "open"]
        launchProcess.running = true
        return true
    }

    function open() {
        root.query = ""
        root.activeModule = ""
        root.selectedIndex = 0
        root.selectedId = ""
        root.fileItems = []
        root.fileQuery = ""
        root.pendingFileQuery = ""
        root.errorMessage = ""
        root.statusMessage = ""
        root.loadActions()
        root.rebuildResults()
    }

    function close() {
        if (filesProcess.running) filesProcess.running = false
        root.pendingFileQuery = ""
        root.statusMessage = ""
    }

    function loadActions() {
        if (root.actionsLoaded || actionsProcess.running || !root.backendBin) return
        root.actionsLoading = true
        actionsProcess.command = [root.backendBin, "json"]
        actionsProcess.running = true
    }

    function appRows(queryValue) {
        if (!root.moduleEnabled("apps") || !root.appLibrary) return []
        return root.appLibrary.appRows(queryValue)
    }

    function actionRows(queryValue) {
        if (!root.moduleEnabled("actions")) return []
        var rows = []
        for (var i = 0; i < root.actionItems.length; i++) {
            var item = root.actionItems[i]
            if (!item || item.runnable !== true || !item.id) continue
            rows.push({
                id: "action:" + item.id,
                kind: "action",
                moduleId: "actions",
                actionId: String(item.id),
                label: String(item.description || item.id),
                subtitle: String(item.category || "Action"),
                detail: String(item.display_key || ""),
                icon: String(item.icon || "system-run"),
                order: 20,
                keywords: String(item.description || "") + " " + String(item.category || "")
            })
        }
        return Search.sortRows(rows, queryValue)
    }

    function shellRows(queryValue) {
        if (!root.moduleEnabled("aurelia-shell")) return []
        var rows = [
            {
                id: "aurelia-shell:reload-plugins",
                kind: "shell-action",
                moduleId: "aurelia-shell",
                shellAction: "reload-plugins",
                label: "Hot Reload Aurelia Plugins",
                subtitle: "Rescan and reload plugin QML",
                detail: "No full shell restart",
                icon: "view-refresh",
                order: 10,
                keywords: "aurelia shell plugin hot reload rescan development"
            },
            {
                id: "aurelia-shell:restart",
                kind: "shell-action",
                moduleId: "aurelia-shell",
                shellAction: "restart",
                label: "Restart Aurelia Shell",
                subtitle: "Restart the resident Quickshell host",
                detail: "Required for shell.qml and host-service changes",
                icon: "system-reboot",
                order: 20,
                keywords: "aurelia shell restart quickshell development"
            }
        ]
        return Search.sortRows(rows, queryValue)
    }

    function fileRows(queryValue) {
        if (!root.moduleEnabled("files") || root.fileQuery !== queryValue) return []
        var rows = []
        for (var i = 0; i < root.fileItems.length; i++) {
            var item = root.fileItems[i]
            if (!item || !item.path) continue
            rows.push({
                id: "file:" + item.path,
                kind: "file",
                moduleId: "files",
                path: String(item.path),
                label: String(item.name || item.path),
                subtitle: item.kind === "directory" ? "Folder" : "File",
                detail: String(item.display_path || item.path),
                icon: item.kind === "directory" ? "folder" : "text-x-generic",
                order: 30,
                keywords: String(item.display_path || item.path)
            })
        }
        return Search.sortRows(rows, queryValue)
    }

    function calculatorRows(queryValue) {
        if (!root.moduleEnabled("calculator") || !Calculator.isExpressionQuery(queryValue)) return []
        var result = Calculator.evaluateQuery(queryValue)
        if (!result.ok) return []
        return [{
            id: "calculator:" + result.expression,
            kind: "calculator",
            moduleId: "calculator",
            value: result.display,
            label: result.display,
            subtitle: "Calculator",
            detail: result.expression + "  ·  Copy result",
            icon: "accessories-calculator",
            order: 5,
            keywords: result.expression
        }]
    }

    function globalRows(queryValue) {
        var rows = root.moduleRegistry ? root.moduleRegistry.moduleRows() : []
        rows = rows.concat(root.appRows(queryValue))
            .concat(root.actionRows(queryValue))
            .concat(root.shellRows(queryValue))
            .concat(root.calculatorRows(queryValue))
            .concat(root.fileRows(queryValue))
        return Search.sortRowsWithFilesLast(rows, queryValue)
    }

    function rebuildResults() {
        var previousId = root.selectedId
        if (!previousId && root.results.length > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.results.length) {
            previousId = root.results[root.selectedIndex].id
        }

        var rows = []
        var queryValue = String(root.query || "").trim()
        if (queryValue === "" && root.activeModule === "") {
            rows = root.moduleRegistry ? root.moduleRegistry.moduleRows() : []
        } else if (root.activeModule === "apps") {
            rows = root.appRows(queryValue)
        } else if (root.activeModule === "actions") {
            rows = root.actionRows(queryValue)
        } else if (root.activeModule === "aurelia-shell") {
            rows = root.shellRows(queryValue)
        } else if (root.activeModule === "files") {
            rows = root.fileRows(queryValue)
        } else if (root.activeModule === "calculator") {
            rows = root.calculatorRows(queryValue)
        } else if (queryValue !== "") {
            rows = root.globalRows(queryValue)
        }

        root.results = queryValue !== "" && root.activeModule === ""
            ? rows
            : Search.sortRows(rows, queryValue)
        if (root.results.length === 0) {
            root.selectedIndex = 0
            root.selectedId = ""
            return
        }

        var nextIndex = -1
        for (var i = 0; i < root.results.length; i++) {
            if (root.results[i].id === previousId) {
                nextIndex = i
                break
            }
        }
        if (nextIndex < 0) nextIndex = Math.min(Math.max(root.selectedIndex, 0), root.results.length - 1)
        root.selectedIndex = nextIndex
        root.selectedId = root.results[nextIndex].id
    }

    function setQuery(value) {
        var next = String(value || "")
        if (root.query === next) return
        root.query = next
        root.selectedIndex = 0
        root.selectedId = ""
        root.errorMessage = ""
        root.rebuildResults()

        if (root.moduleEnabled("files") && (root.activeModule === "files" || next.trim().length >= 2)) {
            root.pendingFileQuery = next.trim()
            fileRequestTimer.restart()
        } else {
            root.pendingFileQuery = ""
            root.fileItems = []
            root.fileQuery = ""
            root.rebuildResults()
        }
    }

    function appendQueryText(value) {
        if (!value) return
        root.setQuery(root.query + String(value))
    }

    function selectIndex(index) {
        if (index < 0 || index >= root.results.length) return
        root.selectedIndex = index
        root.selectedId = root.results[index].id
    }

    function moveSelection(delta) {
        if (root.results.length === 0) return
        var next = (root.selectedIndex + delta) % root.results.length
        if (next < 0) next += root.results.length
        root.selectIndex(next)
    }

    function setModule(id) {
        if (!root.moduleEnabled(id)) return
        fileRequestTimer.stop()
        if (filesProcess.running) filesProcess.running = false
        root.pendingFileQuery = ""
        root.fileItems = []
        root.fileQuery = ""
        root.activeModule = id
        root.query = ""
        root.selectedIndex = 0
        root.selectedId = ""
        root.errorMessage = ""
        root.statusMessage = ""
        if (id === "actions") root.loadActions()
        root.rebuildResults()
    }

    function resetModule() {
        if (!root.activeModule) return
        fileRequestTimer.stop()
        if (filesProcess.running) filesProcess.running = false
        root.activeModule = ""
        root.query = ""
        root.selectedIndex = 0
        root.selectedId = ""
        root.fileItems = []
        root.fileQuery = ""
        root.pendingFileQuery = ""
        root.rebuildResults()
    }

    function activateSelected() {
        if (launchProcess.running || copyProcess.running || shellActionProcess.running || root.results.length === 0) return false
        var row = root.results[root.selectedIndex]
        if (!row) return false
        if (row.kind === "module") {
            if (row.moduleId === "updates") return root.openUpdates()
            if (row.moduleId === "about") return root.openAbout()
            if (row.moduleId === "package-manager") return root.openPackageManager()
            root.setModule(row.moduleId)
            return true
        }
        if (row.kind === "calculator") {
            copyProcess.command = ["wl-copy", String(row.value || "")]
            copyProcess.running = true
            root.statusMessage = "Copying result..."
            return true
        }

        if (row.kind === "shell-action") return root.activateShellAction(row)

        var command = []
        if (row.kind === "app") command = [root.backendBin, "launch-app", row.appId]
        else if (row.kind === "action") command = [root.backendBin, "run", row.actionId]
        else if (row.kind === "file") command = [root.backendBin, "open-path", row.path]
        else return false
        if (!root.backendBin) {
            root.errorMessage = "Command Center backend is unavailable."
            return false
        }
        root.activeLaunchLabel = String(row.label || "item")
        root.statusMessage = "Launching " + root.activeLaunchLabel + "..."
        launchProcess.command = command
        launchProcess.running = true
        return true
    }

    function activateShellAction(row) {
        if (!row || row.kind !== "shell-action") return false
        if (row.shellAction === "reload-plugins") {
            if (!root.shellClientBin) {
                root.errorMessage = "Aurelia Shell IPC client is unavailable."
                return false
            }
            root.activeLaunchLabel = "Hot Reload Aurelia Plugins"
            root.statusMessage = "Requesting plugin reload..."
            shellActionProcess.command = [root.shellClientBin, "shell", "rescanPlugins"]
            shellActionProcess.running = true
            return true
        }
        if (row.shellAction === "restart") {
            if (!root.shellRestartBin) {
                root.errorMessage = "Aurelia Shell restart helper is unavailable."
                return false
            }
            root.activeLaunchLabel = "Restart Aurelia Shell"
            root.statusMessage = "Restarting Aurelia Shell..."
            // The current host will be terminated by the helper. Detach the
            // replacement before the panel is unloaded with the old host.
            Quickshell.execDetached(["setsid", "-f", root.shellRestartBin])
            root.launchFinished(true, "")
            return true
        }
        return false
    }

    property Timer fileRequestTimer: Timer {
        id: fileRequestTimer
        interval: 160
        repeat: false
        onTriggered: {
            if (filesProcess.running) return
            var requested = String(root.pendingFileQuery || "").trim()
            if (requested.length < 2 || !root.moduleEnabled("files")) {
                root.fileItems = []
                root.fileQuery = ""
                root.rebuildResults()
                return
            }
            root.requestedFileQuery = requested
            root.filesLoading = true
            filesProcess.command = [root.backendBin, "files", requested]
            filesProcess.running = true
        }
    }

    property Process actionsProcess: Process {
        id: actionsProcess
        command: []
        environment: root.processEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: actionsStdout }
        stderr: StdioCollector { id: actionsStderr }

        onExited: function(code) {
            root.actionsLoading = false
            if (code !== 0) {
                root.errorMessage = actionsStderr.text.trim() || "Action discovery failed."
                return
            }
            try {
                var parsed = JSON.parse(actionsStdout.text || "[]")
                root.actionItems = Array.isArray(parsed) ? parsed : []
                root.actionsLoaded = true
                root.rebuildResults()
            } catch (error) {
                root.errorMessage = "Action discovery returned invalid data."
            }
        }
    }

    property Process filesProcess: Process {
        id: filesProcess
        command: []
        environment: root.processEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: filesStdout }
        stderr: StdioCollector { id: filesStderr }

        onExited: function(code) {
            root.filesLoading = false
            var completedQuery = root.requestedFileQuery
            if (completedQuery !== String(root.query || "").trim() && root.activeModule !== "files") {
                fileRequestTimer.restart()
                return
            }
            if (code !== 0) {
                root.fileItems = []
                root.fileQuery = ""
                root.errorMessage = filesStderr.text.trim() || "File search failed."
                root.rebuildResults()
                return
            }
            try {
                var parsed = JSON.parse(filesStdout.text || "[]")
                root.fileItems = Array.isArray(parsed) ? parsed : []
                root.fileQuery = completedQuery
                root.rebuildResults()
            } catch (error) {
                root.fileItems = []
                root.fileQuery = ""
                root.errorMessage = "File search returned invalid data."
                root.rebuildResults()
            }
            if (root.pendingFileQuery !== completedQuery) fileRequestTimer.restart()
        }
    }

    property Process launchProcess: Process {
        id: launchProcess
        command: []
        environment: root.processEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: launchStdout }
        stderr: StdioCollector { id: launchStderr }

        onExited: function(code) {
            if (code === 0) {
                console.info("[COMMAND_CENTER] launch.accepted item=" + root.activeLaunchLabel)
                root.statusMessage = ""
                root.launchFinished(true, "")
            } else {
                var message = launchStderr.text.trim() || launchStdout.text.trim() || "Launch failed."
                console.warn("[COMMAND_CENTER] launch.failed code=" + code + " error=" + message)
                root.errorMessage = message
                root.statusMessage = ""
                root.launchFinished(false, message)
            }
        }
    }

    property Process copyProcess: Process {
        id: copyProcess
        command: []
        environment: root.processEnvironment
        clearEnvironment: false
        stderr: StdioCollector { id: copyStderr }

        onExited: function(code) {
            if (code === 0) {
                root.statusMessage = "Result copied."
                root.launchFinished(true, "")
            } else {
                var message = copyStderr.text.trim() || "Could not copy calculator result."
                root.errorMessage = message
                root.statusMessage = ""
                root.launchFinished(false, message)
            }
        }
    }

    property Process shellActionProcess: Process {
        id: shellActionProcess
        command: []
        environment: root.processEnvironment
        clearEnvironment: false
        stdout: StdioCollector { id: shellActionStdout }
        stderr: StdioCollector { id: shellActionStderr }

        onExited: function(code) {
            if (code === 0) {
                console.info("[COMMAND_CENTER] shell_action.accepted item=" + root.activeLaunchLabel)
                root.statusMessage = ""
                root.launchFinished(true, "")
            } else {
                var message = shellActionStderr.text.trim() || shellActionStdout.text.trim() || "Aurelia Shell action failed."
                console.warn("[COMMAND_CENTER] shell_action.failed code=" + code + " error=" + message)
                root.errorMessage = message
                root.statusMessage = ""
                root.launchFinished(false, message)
            }
        }
    }

    property Connections appLibraryConnection: Connections {
        target: root.appLibrary
        function onAppsChanged() { root.rebuildResults() }
    }
}
