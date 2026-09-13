import QtQuick
import Quickshell.Io

// Non-visual Power work belongs here rather than in AureliaKeyboardPanel's
// default contentItem list. The panel receives only QQuickItem content; this
// QObject owns bounded reads, profile operations, and refresh timers.
QtObject {
    id: runtime

    property var owner: null

    function refresh() {
        if (!runtime.owner || !runtime.owner.batteryPresent) return
        if (!runtime.profilesProcess.running) runtime.profilesProcess.running = true
        if (!runtime.systemProcess.running) runtime.systemProcess.running = true
        if (!runtime.memoryProcess.running) runtime.memoryProcess.running = true
    }

    function runCommand(argv, kind) {
        if (!Array.isArray(argv) || argv.length === 0) return "invalid"
        if (!runtime.owner || runtime.owner.actionRunning) return "busy"
        runtime.owner.actionError = ""
        if (typeof runtime.owner.actionExecutor === "function") {
            try {
                var result = runtime.owner.actionExecutor(argv, String(kind || "action"))
                if (result === false || result === "error") {
                    runtime.owner.actionError = "Power action failed."
                    console.error("[POWER] action_failed kind=" + String(kind || "action"))
                    return "error"
                }
                return "ok"
            } catch (error) {
                runtime.owner.actionError = "Power action failed."
                console.error("[POWER] action_failed kind=" + String(kind || "action") +
                    " detail=" + String(error))
                return "error"
            }
        }
        runtime.actionProcess.actionKind = String(kind || "action")
        runtime.actionProcess.command = argv
        runtime.owner.actionRunning = true
        runtime.actionProcess.running = true
        return "pending"
    }

    property Process profilesProcess: Process {
        command: ["/usr/bin/powerprofilesctl", "list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (runtime.owner) runtime.owner.updateProfiles(text)
        }
        onExited: function(code) {
            if (code !== 0 && runtime.owner) {
                runtime.owner.profileError = "Power profile query failed."
                console.error("[POWER] profiles_query_failed code=" + code)
            }
        }
    }

    property Process systemProcess: Process {
        command: ["/usr/bin/uptime"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (runtime.owner) runtime.owner.updateSystemStats(text)
        }
        onExited: function(code) {
            if (code !== 0) console.error("[POWER] system_stats_query_failed code=" + code)
        }
    }

    property Process memoryProcess: Process {
        command: ["/usr/bin/free", "-h"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (runtime.owner) runtime.owner.updateSystemStats(text)
        }
        onExited: function(code) {
            if (code !== 0) console.error("[POWER] memory_stats_query_failed code=" + code)
        }
    }

    property Process actionProcess: Process {
        property string actionKind: "action"
        command: []
        onExited: function(code) {
            if (!runtime.owner) return
            runtime.owner.actionRunning = false
            if (code !== 0) {
                runtime.owner.actionError = "Power action failed."
                console.error("[POWER] action_failed kind=" + actionKind + " code=" + code)
            } else {
                runtime.owner.actionError = ""
                runtime.owner.refresh()
            }
        }
    }

    property Timer refreshTimer: Timer {
        interval: 5000
        repeat: true
        running: !!runtime.owner && runtime.owner.shown
        onTriggered: runtime.refresh()
    }

    property Timer phraseTimer: Timer {
        interval: 2800
        repeat: true
        running: !!runtime.owner && runtime.owner.shown && runtime.owner.activePhrases.length > 0
        onTriggered: {
            if (runtime.owner && runtime.owner.activePhrases.length > 0)
                runtime.owner.phraseIndex = (runtime.owner.phraseIndex + 1) % runtime.owner.activePhrases.length
        }
    }
}
