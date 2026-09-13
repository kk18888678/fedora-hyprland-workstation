import QtQuick
import Quickshell.Io

// Non-visual session commands belong here instead of in the keyboard panel's
// default contentItem list. The panel receives only visual QQuickItem
// children; this QObject owns the single structured-argv action process.
QtObject {
    id: runtime

    property var owner: null
    // Isolated fixtures may substitute a harmless command while keeping the
    // production Process lifecycle. Production leaves this disabled and
    // always executes the structured argv supplied by Model.js.
    property bool testMode: false
    property var testCommand: []

    function runCommand(argv, actionId) {
        if (!Array.isArray(argv) || argv.length === 0) return "invalid"
        if (!runtime.owner || runtime.owner.actionRunning) return "busy"

        runtime.owner.actionError = ""
        if (typeof runtime.owner.actionExecutor === "function") {
            try {
                console.info("[SESSION-ACTIONS] action_started kind=" + String(actionId || "action") +
                    " mode=executor")
                var result = runtime.owner.actionExecutor(argv, String(actionId || "action"))
                if (result === false || result === "error") {
                    runtime.owner.actionError = "Session action failed."
                    console.error("[SESSION-ACTIONS] action_failed kind=" +
                        String(actionId || "action"))
                    return "error"
                }
                console.info("[SESSION-ACTIONS] action_succeeded kind=" + String(actionId || "action") +
                    " mode=executor")
                return "ok"
            } catch (error) {
                runtime.owner.actionError = "Session action failed."
                console.error("[SESSION-ACTIONS] action_failed kind=" +
                    String(actionId || "action") + " detail=" + String(error))
                return "error"
            }
        }

        var processCommand = argv
        if (runtime.testMode && Array.isArray(runtime.testCommand) && runtime.testCommand.length > 0)
            processCommand = runtime.testCommand.slice()
        runtime.actionProcess.actionId = String(actionId || "action")
        runtime.actionProcess.command = processCommand
        runtime.owner.actionRunning = true
        console.info("[SESSION-ACTIONS] action_started kind=" + String(actionId || "action") +
            " mode=process")
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
                console.info("[SESSION-ACTIONS] action_succeeded kind=" + actionId +
                    " mode=process")
            }
        }
    }
}
