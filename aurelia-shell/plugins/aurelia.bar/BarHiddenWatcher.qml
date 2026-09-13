import QtQuick
import Quickshell.Io

// Watches the bar-hidden marker's parent directory. This is a non-visual
// QObject so it can be constructed independently from the PanelWindow bar and
// cannot become an accidental contentItem child.
QtObject {
    id: watcher

    property string directory: ""
    property bool active: false
    property bool unavailable: false
    property bool expectedStop: false
    signal syncRequested(string path)

    function start() {
        if (!watcher.active || watcher.directory === "" || watcher.watchProcess.running) return
        watcher.expectedStop = false
        watcher.unavailable = false
        watcher.watchProcess.running = true
    }

    onActiveChanged: {
        if (!watcher.active) {
            if (watcher.watchProcess.running) {
                watcher.expectedStop = true
                watcher.watchProcess.running = false
            }
        } else {
            watcher.start()
        }
    }

    onDirectoryChanged: {
        if (watcher.watchProcess.running) {
            watcher.expectedStop = true
            watcher.watchProcess.running = false
        }
        watcher.start()
    }

    property Process watchProcess: Process {
        command: watcher.directory === "" ? [] : [
            "/usr/bin/inotifywait", "-m", "-q", "-e", "close_write,create,delete,move",
            "--format", "%w%f", watcher.directory
        ]
        running: false
        stdout: SplitParser {
            onRead: function(path) {
                var changedPath = String(path || "")
                if (changedPath !== "") watcher.syncRequested(changedPath)
            }
        }
        stderr: StdioCollector { id: watchError; waitForEnd: true }
        onExited: function(code) {
            var wasExpected = watcher.expectedStop
            watcher.expectedStop = false
            if (wasExpected || !watcher.active) return
            watcher.unavailable = true
            var detail = String(watchError.text || "").trim()
            console.error("[BAR] hidden_state_watcher_failed code=" + code +
                (detail === "" ? "" : " detail=" + detail))
        }
    }
}
