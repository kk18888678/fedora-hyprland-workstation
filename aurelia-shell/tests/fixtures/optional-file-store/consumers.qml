import QtQuick
import Quickshell
import Quickshell.Io

// Integration fixture for the three consumers that own optional user files.
// Their XDG paths are absent by design; startup must remain warning-free.
ShellRoot {
    id: root

    readonly property string appLibrarySource: Quickshell.env("AURELIA_OPTIONAL_APP_LIBRARY_SOURCE") || ""
    readonly property string commandCenterSource: Quickshell.env("AURELIA_OPTIONAL_COMMAND_CENTER_SOURCE") || ""
    readonly property string menuSource: Quickshell.env("AURELIA_OPTIONAL_MENU_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_OPTIONAL_CONSUMERS_RESULT") || ""
    property bool appLibraryLoaded: false
    property bool commandCenterLoaded: false
    property bool menuLoaded: false
    property bool finished: false

    Loader {
        id: appLibraryLoader
        active: root.appLibrarySource !== ""
        source: root.appLibrarySource
        onLoaded: root.appLibraryLoaded = item !== null
    }

    Loader {
        id: commandCenterLoader
        active: root.commandCenterSource !== ""
        source: root.commandCenterSource
        onLoaded: root.commandCenterLoaded = item !== null
    }

    Loader {
        id: menuLoader
        active: root.menuSource !== ""
        source: root.menuSource
        onLoaded: root.menuLoaded = item !== null
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
            appLibraryLoaded: root.appLibraryLoaded,
            commandCenterLoaded: root.commandCenterLoaded,
            menuLoaded: root.menuLoaded
        }) + "\n")
    }

    Timer {
        interval: 1200
        running: true
        repeat: false
        onTriggered: root.finish()
    }
}
