import QtQuick
import Quickshell
import Quickshell.Io

// Observable optional-file boundary for user-owned configuration.
//
// FileView reports a missing path during construction even when loading is
// blocked. Optional files therefore use a status-probed Process boundary:
// absence is an explicit state, while permission, type, read, and write
// failures retain their diagnostics. Writes arrive through stdin and are
// staged beside the target before an atomic rename.
Item {
    id: root

    property string path: ""
    property bool writable: false
    property bool watchChanges: true
    property int pollInterval: 1000
    property bool exists: false
    property bool ready: false
    property string value: ""
    property string lastError: ""
    property string pendingValue: ""
    property string signature: ""
    property bool writeQueued: false

    onPathChanged: {
        if (root.path !== "") root.reload()
    }

    signal loaded(string value)
    signal loadFailed(string reason)
    signal saved()
    signal saveFailed(string reason)

    function validPath() {
        var value = String(root.path || "")
        return value.charAt(0) === "/" && value !== "/" &&
            value.indexOf("\n") === -1 && value.indexOf("\r") === -1
    }

    function diagnosticDetail(value) {
        var detail = String(value || "").replace(/\s+/g, " ").trim()
        return detail.length > 256 ? detail.substring(0, 256) + "..." : detail
    }

    function reportFailure(reason, detail) {
        root.lastError = String(reason || "optional-file-failure") +
            (detail ? ": " + root.diagnosticDetail(detail) : "")
        console.error("[FILE-STORE] failure path=" + root.path +
            " reason=" + String(reason || "optional-file-failure") +
            (detail ? " detail=" + root.diagnosticDetail(detail) : ""))
        root.ready = true
        root.loadFailed(String(reason || "optional-file-failure"))
    }

    function markMissing() {
        if (root.exists) console.info("[FILE-STORE] optional_file_removed path=" + root.path)
        root.exists = false
        root.ready = true
        root.signature = ""
        root.value = ""
        root.lastError = ""
        root.loaded("")
    }

    function readIfChanged(nextSignature) {
        if (root.signature === nextSignature && root.ready) return
        root.signature = nextSignature
        root.exists = true
        root.ready = false
        if (!readProcess.running) readProcess.running = true
    }

    function reload() {
        if (!root.validPath()) {
            root.reportFailure("invalid-path", "optional file path must be absolute")
            return
        }
        if (!probeProcess.running) probeProcess.running = true
    }

    // Compatibility names for existing FileView-backed owners. The store's
    // write remains asynchronous; callers observe completion through saved or
    // saveFailed rather than assuming a successful mutation before the rename.
    function text() { return root.value }
    function setText(nextValue) { return root.setValue(nextValue) }

    function setValue(nextValue) {
        if (!root.writable) {
            root.reportFailure("write-not-permitted", "store is read-only")
            return false
        }
        if (!root.validPath()) {
            root.reportFailure("invalid-path", "optional file path must be absolute")
            return false
        }
        root.pendingValue = String(nextValue || "")
        root.lastError = ""
        if (writeProcess.running) {
            // A state owner may publish several adjacent updates while the
            // previous atomic rename is in flight. Keep the newest complete
            // value and serialize it after the current write; this is a
            // coalesced update, not a failed write.
            root.writeQueued = true
            return true
        }
        writeProcess.stdinEnabled = true
        writeProcess.running = true
        return true
    }

    Process {
        id: probeProcess
        command: ["/usr/bin/stat", "-c", "%F:%s:%Y", root.path]
        running: false
        stdout: StdioCollector { id: probeStdout; waitForEnd: true }
        stderr: StdioCollector { id: probeStderr; waitForEnd: true }
        onExited: function(code) {
            var detail = root.diagnosticDetail(probeStderr.text)
            if (code !== 0) {
                if (code === 1 && (detail.indexOf("No such file") !== -1 ||
                    detail.indexOf("cannot stat") !== -1)) {
                    root.markMissing()
                } else {
                    root.reportFailure("probe-failed", "code=" + code +
                        (detail ? " detail=" + detail : ""))
                }
                return
            }

            var stat = String(probeStdout.text || "").trim()
            if (stat.indexOf("regular ") !== 0) {
                root.reportFailure("invalid-file-type", stat)
                return
            }
            root.readIfChanged(stat)
        }
    }

    Process {
        id: readProcess
        command: ["/usr/bin/cat", root.path]
        running: false
        stdout: StdioCollector { id: readStdout; waitForEnd: true }
        stderr: StdioCollector { id: readStderr; waitForEnd: true }
        onExited: function(code) {
            var detail = root.diagnosticDetail(readStderr.text)
            if (code !== 0) {
                root.signature = ""
                root.reportFailure("read-failed", "code=" + code +
                    (detail ? " detail=" + detail : ""))
                return
            }
            root.value = String(readStdout.text || "")
            root.lastError = ""
            root.ready = true
            root.loaded(root.value)
        }
    }

    Process {
        id: writeProcess
        command: ["/usr/bin/bash", "-c",
            "set -Eeuo pipefail\n" +
            "path=\"$1\"\n" +
            "directory=\"$(dirname -- \"$path\")\"\n" +
            "mkdir -p -- \"$directory\"\n" +
            "temporary=\"$(mktemp \"$directory/.aurelia-file.XXXXXX\")\"\n" +
            "cleanup() { rm -f -- \"$temporary\"; }\n" +
            "trap cleanup EXIT\n" +
            "cat >\"$temporary\"\n" +
            "chmod 0600 -- \"$temporary\"\n" +
            "mv -T -- \"$temporary\" \"$path\"\n" +
            "trap - EXIT\n", "aurelia-optional-file-store", root.path]
        running: false
        stdinEnabled: true
        stdout: StdioCollector { id: writeStdout; waitForEnd: true }
        stderr: StdioCollector { id: writeStderr; waitForEnd: true }
        onStarted: {
            write(root.pendingValue)
            stdinEnabled = false
        }
        onExited: function(code) {
            var detail = root.diagnosticDetail(writeStderr.text)
            if (code !== 0) {
                root.writeQueued = false
                root.reportFailure("write-failed", "code=" + code +
                    (detail ? " detail=" + detail : ""))
                root.saveFailed("write-failed")
                return
            }
            if (root.writeQueued) {
                root.writeQueued = false
                writeProcess.stdinEnabled = true
                writeProcess.running = true
                return
            }
            root.lastError = ""
            root.saved()
            root.reload()
        }
    }

    Timer {
        interval: Math.max(250, root.pollInterval)
        repeat: true
        running: root.watchChanges
        onTriggered: root.reload()
    }

    Component.onCompleted: {
        if (root.path !== "") root.reload()
    }
}
