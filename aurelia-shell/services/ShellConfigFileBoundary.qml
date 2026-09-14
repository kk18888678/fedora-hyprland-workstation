import QtQuick
import Quickshell
import Quickshell.Io

// Owns presence detection and first-run bootstrap for the user-owned
// shell.json. A FileView is deliberately kept out of the missing-file state;
// this boundary only exposes verified regular-file transitions to ShellConfig.
Item {
    id: boundary

    property string path: ""
    property string bootstrapText: ""
    property var owner: null
    property bool bootstrapAttempted: false
    property string signature: ""

    property FileView configFile: FileView {
        // Keep the file reader dormant until the owner has verified that the
        // path exists. This component owns the FileView callbacks so the
        // ShellConfig facade can expose the same stable configFile object.
        path: boundary.owner && (boundary.owner.configFileReady ||
            boundary.owner.explicitConfigPath) ? boundary.path : ""
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true

        onSaved: {
            if (boundary.owner) {
                boundary.owner.lastSaveOk = true
                boundary.owner.secureConfigPermissions()
            }
        }
        onSaveFailed: {
            if (boundary.owner) {
                boundary.owner.lastSaveOk = false
                if (boundary.owner.migrationInProgress)
                    boundary.owner.finishMigrationSave(false)
            }
        }
        onLoaded: if (boundary.owner) boundary.owner.reload()
    }

    signal fileAvailable(string signature)
    signal fileMissing()
    signal bootstrapStarted()
    signal bootstrapSaved()
    signal bootstrapFailed(string reason)
    signal probeFailed(string reason)

    function validPath() {
        return boundary.path.charAt(0) === "/" && boundary.path !== "/" &&
            boundary.path.indexOf("\n") === -1 && boundary.path.indexOf("\r") === -1
    }

    function detail(value) {
        return String(value || "").replace(/\s+/g, " ").trim()
    }

    function probe() {
        if (!boundary.validPath() || presenceProbe.running) {
            if (!boundary.validPath()) {
                var invalid = "shell config path must be absolute"
                console.error("[SHELL-CONFIG] presence_probe_failed reason=" + invalid)
                boundary.probeFailed(invalid)
            }
            return
        }
        presenceProbe.running = true
    }

    OptionalFileStore {
        id: bootstrapStore
        path: boundary.path
        writable: true
        watchChanges: false

        onSaved: boundary.bootstrapSaved()
        onSaveFailed: function(reason) { boundary.bootstrapFailed(String(reason || "write-failed")) }
    }

    Process {
        id: presenceProbe
        command: boundary.validPath()
            ? ["/usr/bin/stat", "-c", "%F:%s:%Y", boundary.path]
            : ["/usr/bin/false"]
        running: false
        stdout: StdioCollector { id: presenceStdout; waitForEnd: true }
        stderr: StdioCollector { id: presenceStderr; waitForEnd: true }

        onExited: function(code) {
            var errorText = boundary.detail(presenceStderr.text)
            if (code !== 0) {
                var missing = code === 1 && (errorText.indexOf("No such file") !== -1 ||
                    errorText.indexOf("cannot stat") !== -1)
                if (!missing) {
                    var reason = "code=" + code + (errorText ? " detail=" + errorText : "")
                    console.error("[SHELL-CONFIG] presence_probe_failed " + reason)
                    boundary.probeFailed(reason)
                } else {
                    boundary.signature = ""
                    boundary.fileMissing()
                    if (!boundary.bootstrapAttempted) {
                        boundary.bootstrapAttempted = true
                        boundary.bootstrapStarted()
                        if (!bootstrapStore.setText(boundary.bootstrapText))
                            boundary.bootstrapFailed("write-not-started")
                    }
                }
                return
            }

            var nextSignature = String(presenceStdout.text || "").trim()
            if (nextSignature.indexOf("regular ") !== 0) {
                var typeReason = "not a regular file"
                console.error("[SHELL-CONFIG] invalid_file_type detail=" + nextSignature)
                boundary.probeFailed(typeReason)
                return
            }
            if (boundary.signature !== nextSignature) {
                boundary.signature = nextSignature
                boundary.fileAvailable(nextSignature)
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: boundary.probe()
    }

    Component.onCompleted: boundary.probe()
}
