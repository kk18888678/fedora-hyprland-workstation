import QtQuick
import Quickshell
import Quickshell.Io

// T10 state fixture. ShellConfig is loaded as the real component, but every
// path is supplied by the test's temporary home/config sandbox.
ShellRoot {
    id: root

    readonly property string configSource: Quickshell.env("AURELIA_STATE_CONFIG_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_STATE_RESULT") || ""
    property var stateConfig: null
    property bool started: false
    property bool finishing: false

    Loader {
        id: configLoader
        source: root.configSource
        onLoaded: {
            root.stateConfig = item
            poll.start()
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function finish() {
        if (root.finishing || !root.stateConfig) return
        root.finishing = true
        var raw = ""
        try { raw = root.stateConfig.configFile.text() } catch (e) {}
        resultFile.setText(JSON.stringify({
            migrationNeededBefore: root.migrationNeededBefore,
            migrationReturn: root.migrationReturn,
            migrationResult: root.stateConfig.migrationResult,
            migrationNeededAfter: root.stateConfig.migrationNeeded,
            config: root.stateConfig.config,
            raw: raw
        }) + "\n")
    }

    property bool migrationNeededBefore: false
    property string migrationReturn: ""

    Timer {
        id: poll
        interval: 200
        repeat: true
        onTriggered: {
            if (!root.stateConfig || root.stateConfig.revision < 1) return
            if (!root.started) {
                root.started = true
                root.migrationNeededBefore = root.stateConfig.migrationNeeded
                root.migrationReturn = root.stateConfig.migrate()
                return
            }
            if (!root.stateConfig.migrationInProgress && root.stateConfig.migrationResult !== "backing-up") {
                poll.stop()
                root.finish()
            }
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
