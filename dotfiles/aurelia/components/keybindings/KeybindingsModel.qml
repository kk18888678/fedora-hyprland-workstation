import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property var allItems: []
    property var filteredItems: []
    property string searchQuery: ""
    property int selectedIndex: 0
    property bool isLoading: false
    property string statusMessage: ""

    // Inline Keybinding Operation State Machine
    // States: "idle" | "capturing" | "applying" | "success" | "conflict" | "error"
    property string operationState: "idle"
    property string operationMessage: ""

    // Concurrency state bounds
    property bool isReloading: fetchProcess.running
    property bool isExecuting: runProcess.running
    property bool isMutating: setProcess.running || unsetProcess.running

    readonly property var selectedItem: (filteredItems && filteredItems.length > selectedIndex && selectedIndex >= 0)
        ? filteredItems[selectedIndex]
        : null

    onSearchQueryChanged: {
        filterItems()
    }

    Component.onCompleted: {
        reload()
    }

    property var reloadStartTime: 0

    function reload() {
        // Concurrency guard: avoid re-entry if a fetch operation is already in progress
        if (root.isReloading) return;
        if (fetchProcess.running) {
            console.warn("[PERF-WARN] KeybindingsModel: reload() ignored because fetchProcess is currently running")
            return
        }
        isLoading = true
        statusMessage = ""
        reloadStartTime = Date.now()
        fetchProcess.running = true
    }

    function filterItems() {
        var t0 = Date.now()
        var query = (searchQuery || "").trim().toLowerCase()
        var currentSelectedId = selectedItem ? selectedItem.id : ""

        if (query === "") {
            filteredItems = allItems.slice()
        } else {
            var tokens = query.split(/\s+/).filter(function(t) { return t.length > 0; })
            filteredItems = allItems.filter(function(item) {
                // Natural search over displayed key and action/application title
                var target = ((item.display_key || "") + " " + (item.description || "")).toLowerCase()
                for (var i = 0; i < tokens.length; i++) {
                    if (target.indexOf(tokens[i]) === -1) {
                        return false
                    }
                }
                return true
            })
        }

        // Preserve keyboard selection across query modifications
        if (filteredItems.length === 0) {
            selectedIndex = -1
        } else {
            var newIndex = -1
            if (currentSelectedId !== "") {
                for (var j = 0; j < filteredItems.length; j++) {
                    if (filteredItems[j].id === currentSelectedId) {
                        newIndex = j
                        break
                    }
                }
            }
            if (newIndex !== -1) {
                selectedIndex = newIndex
            } else if (selectedIndex >= filteredItems.length || selectedIndex < 0) {
                selectedIndex = 0
            }
        }

        var filterElapsed = Date.now() - t0
        if (filterElapsed > 15) {
            console.warn("[PERF-WARN] KeybindingsModel: filterItems took " + filterElapsed + "ms for query '" + query + "' (" + filteredItems.length + " matches)")
        }
    }

    function selectNext() {
        if (filteredItems.length === 0) return
        if (selectedIndex < filteredItems.length - 1) {
            selectedIndex++
        }
    }

    function selectPrevious() {
        if (filteredItems.length === 0) return
        if (selectedIndex > 0) {
            selectedIndex--
        }
    }

    property FileView binKeybindingsCheck: FileView {
        path: "/usr/local/bin/workstation-keybindings"
        printErrors: false
    }

    property FileView binHotkeysCheck: FileView {
        path: "/usr/local/bin/workstation-hotkeys"
        printErrors: false
    }

    // Deterministic backend executable resolution:
    // 1. Test override via WORKSTATION_KEYBINDINGS_BIN environment variable
    // 2. Managed system installation: /usr/local/bin/workstation-keybindings
    // 3. System PATH: workstation-keybindings
    // 4. Compatibility fallback: /usr/local/bin/workstation-hotkeys, workstation-hotkeys
    // Invariant: Stale ~/.local/bin cannot shadow the managed workstation installation.
    readonly property string backendBin: {
        var testOverride = Quickshell.env("WORKSTATION_KEYBINDINGS_BIN") || Quickshell.env("WORKSTATION_HOTKEYS_BIN") || ""
        if (testOverride !== "") {
            return testOverride
        }
        try {
            var kbTxt = binKeybindingsCheck.text()
            if (kbTxt && kbTxt.length > 0) {
                return "/usr/local/bin/workstation-keybindings"
            }
        } catch (e) {}
        try {
            var hkTxt = binHotkeysCheck.text()
            if (hkTxt && hkTxt.length > 0) {
                return "/usr/local/bin/workstation-hotkeys"
            }
        } catch (e) {}
        return "/usr/local/bin/workstation-keybindings"
    }

    readonly property var procEnv: ({
        "PATH": "/usr/local/bin:/usr/bin:/bin" + (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : "")
    })

    property var runStartTime: 0

    function resetOperation() {
        root.operationState = "idle"
        root.operationMessage = ""
    }

    function runSelected() {
        if (root.isExecuting) return;
        var item = selectedItem
        if (!item) return false
        if (item.runnable !== true) {
            return false
        }

        if (runProcess.running) {
            console.warn("[PERF-WARN] KeybindingsModel: runSelected() ignored because runProcess is currently running")
            return false
        }

        // Direct structured argv execution through hardened backend
        runStartTime = Date.now()
        runProcess.command = [root.backendBin, "run", item.id]
        runProcess.environment = root.procEnv
        runProcess.running = true
        console.info("[PERF] KeybindingsModel: Dispatching run action '" + item.id + "'")
        return true
    }

    function setShortcut(actionId, newKey) {
        if (!actionId || !newKey) return
        if (root.isMutating) return;
        if (setProcess.running) {
            console.warn("[PERF-WARN] KeybindingsModel: setShortcut() ignored because setProcess is currently running")
            return
        }
        console.info("[PERF] KeybindingsModel: Setting shortcut for '" + actionId + "' to '" + newKey + "'")
        root.operationState = "applying"
        root.operationMessage = "Applying shortcut..."
        setProcess.command = [root.backendBin, "set", actionId, newKey]
        setProcess.environment = root.procEnv
        setProcess.running = true
    }

    function unsetShortcut(actionId) {
        if (!actionId) return
        if (root.isMutating) return;
        if (unsetProcess.running) {
            console.warn("[PERF-WARN] KeybindingsModel: unsetShortcut() ignored because unsetProcess is currently running")
            return
        }
        console.info("[PERF] KeybindingsModel: Unsetting shortcut for '" + actionId + "'")
        root.operationState = "applying"
        root.operationMessage = "Unsetting shortcut..."
        unsetProcess.command = [root.backendBin, "unset", actionId]
        unsetProcess.environment = root.procEnv
        unsetProcess.running = true
    }

    // Backend process to fetch structured JSON
    property Process fetchProcess: Process {
        command: [root.backendBin, "json"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoading = false
                var fetchDuration = root.reloadStartTime > 0 ? (Date.now() - root.reloadStartTime) : 0
                var parseT0 = Date.now()
                try {
                    var parsed = JSON.parse(this.text)
                    var parseDuration = Date.now() - parseT0
                    if (Array.isArray(parsed)) {
                        root.allItems = parsed
                        root.filterItems()
                        if (fetchDuration > 300 || parseDuration > 20) {
                            console.warn("[PERF-WARN] KeybindingsModel: Fetched " + parsed.length + " shortcuts in " + fetchDuration + "ms (JSON parse: " + parseDuration + "ms)")
                        } else {
                            console.info("[PERF] KeybindingsModel: Fetched " + parsed.length + " shortcuts in " + fetchDuration + "ms (JSON parse: " + parseDuration + "ms)")
                        }
                    }
                } catch (e) {
                    console.error("[ERROR] KeybindingsModel: Failed to parse shortcut metadata: " + e + ", raw: " + this.text)
                    root.statusMessage = "Failed to parse shortcut metadata: " + e
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim()) {
                    console.error("[ERROR] KeybindingsModel: fetchProcess stderr: " + this.text.trim())
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                console.error("[ERROR] KeybindingsModel: fetchProcess exited with code: " + code)
                root.statusMessage = "Failed to fetch shortcut metadata (exit " + code + ")"
            }
        }
    }

    // Backend process to run actions detached
    property Process runProcess: Process {
        command: [root.backendBin, "run", ""]
        environment: root.procEnv
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim()) {
                    console.error("[ERROR] KeybindingsModel: runProcess stderr: " + this.text.trim())
                }
            }
        }
        onExited: function(code) {
            var elapsed = root.runStartTime > 0 ? (Date.now() - root.runStartTime) : 0
            if (code !== 0) {
                console.error("[ERROR] KeybindingsModel: runProcess exited with code " + code + " after " + elapsed + "ms")
            } else {
                console.info("[PERF] KeybindingsModel: runProcess finished successfully in " + elapsed + "ms")
            }
        }
    }

    // Backend process to set shortcut (non-interactive inline execution)
    property Process setProcess: Process {
        command: [root.backendBin, "set", "", ""]
        environment: root.procEnv
        property string errorText: ""
        stderr: StdioCollector {
            onStreamFinished: {
                setProcess.errorText = this.text ? this.text.trim() : ""
            }
        }
        onExited: function(code) {
            if (code === 0) {
                root.operationState = "success"
                root.operationMessage = "Shortcut updated successfully."
                console.info("[PERF] KeybindingsModel: setProcess completed successfully")
                root.reload()
            } else {
                var msg = setProcess.errorText || "Failed to set shortcut."
                if (msg.indexOf("Conflict") !== -1 || msg.indexOf("already bound") !== -1) {
                    root.operationState = "conflict"
                } else {
                    root.operationState = "error"
                }
                root.operationMessage = msg
                console.error("[ERROR] KeybindingsModel: setProcess failed (code " + code + "): " + msg)
            }
        }
    }

    // Backend process to unset shortcut (non-interactive inline execution)
    property Process unsetProcess: Process {
        command: [root.backendBin, "unset", ""]
        environment: root.procEnv
        property string errorText: ""
        stderr: StdioCollector {
            onStreamFinished: {
                unsetProcess.errorText = this.text ? this.text.trim() : ""
            }
        }
        onExited: function(code) {
            if (code === 0) {
                root.operationState = "success"
                root.operationMessage = "Shortcut unbound successfully."
                console.info("[PERF] KeybindingsModel: unsetProcess completed successfully")
                root.reload()
            } else {
                root.operationState = "error"
                root.operationMessage = unsetProcess.errorText || "Failed to unbind shortcut."
                console.error("[ERROR] KeybindingsModel: unsetProcess failed (code " + code + "): " + root.operationMessage)
            }
        }
    }
}
