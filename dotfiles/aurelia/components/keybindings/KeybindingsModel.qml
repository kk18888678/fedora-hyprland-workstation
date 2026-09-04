import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property var allItems: []
    property var boundItems: []
    property var unboundItems: []
    property var availableApplications: []
    property var filteredItems: []

    // Views: "bound" | "unbound" | "add_app"
    property string activeView: "bound"
    readonly property int boundCount: boundItems.length
    readonly property int unboundCount: unboundItems.length
    readonly property int appsCount: availableApplications.length

    property string searchQuery: ""
    property int selectedIndex: 0
    property bool isLoading: fetchProcess.running || appsProcess.running
    property bool isLoadingApps: appsProcess.running
    property string statusMessage: ""
    property string appsStatusMessage: ""

    // Inline Keybinding Operation State Machine
    // States: "idle" | "capturing" | "applying" | "success" | "conflict" | "error"
    property string operationState: "idle"
    property string operationMessage: ""

    // Concurrency state bounds
    property bool isReloading: fetchProcess.running
    property bool isExecuting: runProcess.running
    property bool isMutating: setProcess.running || unsetProcess.running || addAppProcess.running

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

    function switchView(view) {
        if (view !== "bound" && view !== "unbound" && view !== "add_app") return;
        if (root.activeView === view) return;
        root.activeView = view;
        root.searchQuery = "";
        root.selectedIndex = 0;
        root.resetOperation();
        if (view === "add_app") {
            if (!root.availableApplications || root.availableApplications.length === 0) {
                root.loadApplications();
            }
        }
        root.filterItems();
    }

    function toggleView() {
        if (root.activeView === "bound") {
            root.switchView("unbound");
        } else {
            root.switchView("bound");
        }
    }

    function loadApplications() {
        if (appsProcess.running) return;
        root.isLoadingApps = true;
        root.appsStatusMessage = "";
        appsProcess.running = true;
    }

    function addApplication(desktopId) {
        if (!desktopId) return;
        if (root.isMutating) return;
        if (addAppProcess.running) {
            console.warn("[PERF-WARN] KeybindingsModel: addApplication() ignored because addAppProcess is currently running")
            return;
        }
        console.info("[PERF] KeybindingsModel: Adding application action for '" + desktopId + "'")
        root.operationState = "applying"
        root.operationMessage = "Adding application..."
        addAppProcess.command = [root.backendBin, "add-app", desktopId]
        addAppProcess.environment = root.procEnv
        addAppProcess.running = true
    }

    function filterItems() {
        var t0 = Date.now()
        var query = (searchQuery || "").trim().toLowerCase()
        var currentSelectedId = selectedItem ? selectedItem.id : ""

        var sourceList = []
        if (root.activeView === "add_app") {
            sourceList = root.availableApplications
        } else if (root.activeView === "unbound") {
            sourceList = root.unboundItems
        } else {
            sourceList = root.boundItems
        }

        if (query === "") {
            filteredItems = sourceList.slice()
        } else {
            var tokens = query.split(/\s+/).filter(function(t) { return t.length > 0; })
            filteredItems = sourceList.filter(function(item) {
                var target = ""
                if (root.activeView === "add_app") {
                    target = ((item.display_key || "") + " " + (item.description || "") + " " + (item.categories || "") + " " + (item.comment || "")).toLowerCase()
                } else {
                    target = ((item.display_key || "") + " " + (item.description || "")).toLowerCase()
                }
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
                        var bList = []
                        var uList = []
                        for (var k = 0; k < parsed.length; k++) {
                            var it = parsed[k]
                            if (it.unbound === true || !it.key || it.display_key === "None (Unbound)") {
                                uList.push(it)
                            } else {
                                bList.push(it)
                            }
                        }
                        root.boundItems = bList
                        root.unboundItems = uList
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

    // Backend process to discover installed graphical applications
    property Process appsProcess: Process {
        command: [root.backendBin, "apps"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoadingApps = false
                try {
                    var parsed = JSON.parse(this.text)
                    if (Array.isArray(parsed)) {
                        var appList = []
                        for (var i = 0; i < parsed.length; i++) {
                            var a = parsed[i]
                            var desc = a.name || a.desktop_id
                            if (a.generic_name && a.generic_name !== a.name) {
                                desc = desc + " — " + a.generic_name
                            }
                            appList.push({
                                id: "app:" + a.desktop_id,
                                desktop_id: a.desktop_id,
                                description: desc,
                                display_key: a.desktop_id,
                                icon: a.icon || "",
                                categories: a.categories || "",
                                comment: a.comment || "",
                                runnable: false,
                                editable: true
                            })
                        }
                        root.availableApplications = appList
                        if (root.activeView === "add_app") {
                            root.filterItems()
                        }
                    }
                } catch (e) {
                    console.error("[ERROR] KeybindingsModel: Failed to parse applications: " + e)
                    root.appsStatusMessage = "Failed to load applications: " + e
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim()) {
                    console.error("[ERROR] KeybindingsModel: appsProcess stderr: " + this.text.trim())
                }
            }
        }
        onExited: function(code) {
            root.isLoadingApps = false
            if (code !== 0) {
                console.error("[ERROR] KeybindingsModel: appsProcess exited with code: " + code)
                root.appsStatusMessage = "Failed to fetch applications (exit " + code + ")"
            }
        }
    }

    // Backend process to add application action
    property Process addAppProcess: Process {
        command: [root.backendBin, "add-app", ""]
        environment: root.procEnv
        property string errorText: ""
        stderr: StdioCollector {
            onStreamFinished: {
                addAppProcess.errorText = this.text ? this.text.trim() : ""
            }
        }
        onExited: function(code) {
            if (code === 0) {
                root.operationState = "success"
                root.operationMessage = "Application added to Unbound actions."
                console.info("[PERF] KeybindingsModel: addAppProcess completed successfully")
                root.reload()
                root.switchView("unbound")
            } else {
                root.operationState = "error"
                root.operationMessage = addAppProcess.errorText || "Failed to add application."
                console.error("[ERROR] KeybindingsModel: addAppProcess failed (code " + code + "): " + root.operationMessage)
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
