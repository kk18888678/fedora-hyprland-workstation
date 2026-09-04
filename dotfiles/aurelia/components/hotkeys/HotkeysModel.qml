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

    readonly property var selectedItem: (filteredItems && filteredItems.length > selectedIndex && selectedIndex >= 0)
        ? filteredItems[selectedIndex]
        : null

    onSearchQueryChanged: {
        filterItems()
    }

    Component.onCompleted: {
        reload()
    }

    function reload() {
        isLoading = true
        fetchProcess.running = true
    }

    function filterItems() {
        var query = (searchQuery || "").trim().toLowerCase()
        var currentSelectedId = selectedItem ? selectedItem.id : ""

        if (query === "") {
            filteredItems = allItems.slice()
        } else {
            var tokens = query.split(/\s+/).filter(function(t) { return t.length > 0; })
            filteredItems = allItems.filter(function(item) {
                // Natural search over displayed hotkey and action/application title
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

    readonly property string hotkeysBin: {
        var home = Quickshell.env("HOME") || ""
        if (home && home.length > 0) {
            return home + "/.local/bin/workstation-hotkeys"
        }
        return "workstation-hotkeys"
    }

    readonly property var procEnv: ({
        "PATH": (Quickshell.env("HOME") ? Quickshell.env("HOME") + "/.local/bin:" : "") + (Quickshell.env("PATH") || "/usr/local/bin:/usr/bin")
    })

    function runSelected() {
        var item = selectedItem
        if (!item) return false
        if (item.runnable !== true) {
            return false
        }

        // Direct structured argv execution through hardened backend
        runProcess.command = [root.hotkeysBin, "run", item.id]
        runProcess.environment = root.procEnv
        runProcess.running = true
        return true
    }

    function setShortcut(actionId, newKey) {
        if (!actionId) return
        if (newKey && newKey !== "") {
            setProcess.command = [root.hotkeysBin, "set", actionId, newKey]
        } else {
            setProcess.command = [root.hotkeysBin, "set", actionId]
        }
        setProcess.environment = root.procEnv
        setProcess.running = true
    }

    function unsetShortcut(actionId) {
        if (!actionId) return
        unsetProcess.command = [root.hotkeysBin, "unset", actionId]
        unsetProcess.environment = root.procEnv
        unsetProcess.running = true
    }

    // Backend process to fetch structured JSON
    property Process fetchProcess: Process {
        command: [root.hotkeysBin, "json"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                root.isLoading = false
                try {
                    var parsed = JSON.parse(this.text)
                    if (Array.isArray(parsed)) {
                        root.allItems = parsed
                        root.filterItems()
                    }
                } catch (e) {
                    console.error("Failed to parse shortcut metadata: " + e + ", raw output: " + this.text)
                    root.statusMessage = "Failed to parse shortcut metadata: " + e
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim()) {
                    console.error("fetchProcess stderr: " + this.text.trim())
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                console.error("fetchProcess exited with code: " + code)
                root.statusMessage = "Failed to fetch shortcut metadata (exit " + code + ")"
            }
        }
    }

    // Backend process to run actions detached
    property Process runProcess: Process {
        command: [root.hotkeysBin, "run", ""]
        environment: root.procEnv
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim()) {
                    console.error("runProcess stderr: " + this.text.trim())
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                console.error("runProcess exited with code: " + code)
            }
        }
    }

    // Backend process to capture physical key
    property Process setProcess: Process {
        command: [root.hotkeysBin, "set", ""]
        environment: root.procEnv
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim()) {
                    console.error("setProcess stderr: " + this.text.trim())
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                console.error("setProcess exited with code: " + code)
            }
            root.reload()
        }
    }

    // Backend process to unset shortcut
    property Process unsetProcess: Process {
        command: [root.hotkeysBin, "unset", ""]
        environment: root.procEnv
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim()) {
                    console.error("unsetProcess stderr: " + this.text.trim())
                }
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                console.error("unsetProcess exited with code: " + code)
            }
            root.reload()
        }
    }
}

