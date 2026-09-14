import QtQuick
import Quickshell
import Quickshell.Io

// Disposable contract fixture for optional user-owned files. The target is
// intentionally absent at startup so a missing optional file must be an
// explicit state, not a QML FileView warning.
ShellRoot {
    id: root

    readonly property string targetPath: Quickshell.env("AURELIA_OPTIONAL_FILE_TARGET") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_OPTIONAL_FILE_RESULT") || ""
    readonly property string storeSource: Quickshell.env("AURELIA_OPTIONAL_FILE_STORE_SOURCE") || ""
    property int stage: 0
    property bool missingObserved: false
    property bool firstRead: false
    property bool secondRead: false
    property bool writeFailed: false
    property int saveCount: 0
    property bool finished: false

    Loader {
        id: store
        active: true
        source: root.storeSource
        onLoaded: {
            item.writable = true
            item.watchChanges = false
            item.pollInterval = 100
            item.path = root.targetPath
        }
    }

    Connections {
        target: store.item

        function onLoaded(value) {
            var content = String(value || "")
            if (root.stage === 0) {
                root.missingObserved = content === ""
                root.stage = 1
                if (!store.item.setValue("first\n")) root.writeFailed = true
            } else if (root.stage === 1 && content === "first\n") {
                root.firstRead = true
                root.stage = 2
                if (!store.item.setValue("second\n")) root.writeFailed = true
            } else if (root.stage === 2 && content === "second\n") {
                root.secondRead = true
                root.finish()
            }
        }

        function onLoadFailed(reason) {
            root.writeFailed = true
            console.error("[OPTIONAL-FILE-TEST] load_failed reason=" + reason)
        }

        function onSaved() { root.saveCount++ }

        function onSaveFailed(reason) {
            root.writeFailed = true
            console.error("[OPTIONAL-FILE-TEST] save_failed reason=" + reason)
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function finish() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify({
            missingObserved: root.missingObserved,
            firstRead: root.firstRead,
            secondRead: root.secondRead,
            writeFailed: root.writeFailed,
            saveCount: root.saveCount,
            finalValue: store.item ? store.item.value : "",
            exists: store.item ? store.item.exists : false,
            ready: store.item ? store.item.ready : false
        }) + "\n")
    }

    Timer {
        interval: 6000
        running: true
        repeat: false
        onTriggered: root.finish()
    }
}
