import QtQuick
import Quickshell.Io

// Non-visual session commands belong here instead of in the keyboard panel's
// default contentItem list. The panel receives only visual QQuickItem
// children; this QObject owns the single structured-argv action process.
QtObject {
    id: runtime

    property var owner: null

    function runCommand(argv, actionId) {
        if (!Array.isArray(argv) || argv.length === 0) return "invalid"
        if (!runtime.owner || runtime.owner.actionRunning) return "busy"

        runtime.owner.actionError = ""
        if (typeof runtime.owner.actionExecutor === "function") {
            try {
                var result = runtime.owner.actionExecutor(argv, String(actionId || "action"))
                if (result === false || result === "error") {
                    runtime.owner.actionError = "Session action failed."
                    console.error("[SESSION-ACTIONS] action_failed kind=" +
                        String(actionId || "action"))
                    return "error"
                }
                return "ok"
            } catch (error) {
                runtime.owner.actionError = "Session action failed."
                console.error("[SESSION-ACTIONS] action_failed kind=" +
                    String(actionId || "action") + " detail=" + String(error))
                return "error"
            }
        }

        runtime.actionProcess.actionId = String(actionId || "action")
        runtime.actionProcess.command = argv
        runtime.owner.actionRunning = true
        runtime.actionProcess.running = true
        return "pending"
    }

    property Process actionProcess: Process {
        property string actionId: "action"
        command: []

        onExited: function(code) {
            if (!runtime.owner) return
            runtime.owner.actionRunning = false
            if (code !== 0) {
                runtime.owner.actionError = "Session action failed."
                console.error("[SESSION-ACTIONS] action_failed kind=" + actionId +
                    " code=" + code)
            } else {
                runtime.owner.actionError = ""
            }
        }
    }
}
