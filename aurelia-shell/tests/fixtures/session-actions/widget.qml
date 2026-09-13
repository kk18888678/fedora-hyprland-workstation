import QtQuick
import Quickshell
import Quickshell.Io

// T47 widget fixture. Loader.setSource supplies the fake panel before the real
// bar widget is constructed, so the production panel window is never created.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_SESSION_WIDGET_RESULT") || ""
    readonly property string widgetSource: Quickshell.env("AURELIA_SESSION_WIDGET_SOURCE") || ""
    property bool finished: false

    QtObject {
        id: fakePanel
        property bool shown: false

        function open(payloadJson) { shown = true; return "ok" }
        function close() { shown = false; return "ok" }
    }

    Loader {
        id: widgetLoader
        onLoaded: {
            if (!item) return
            var initialVisible = item.visible === true
            var initialWidth = item.implicitWidth
            var openResult = item.handleClick(Qt.LeftButton)
            var shownAfterOpen = fakePanel.shown
            var closeResult = item.handleClick(Qt.LeftButton)
            var shownAfterClose = fakePanel.shown
            root.writeResult({
                loaded: true,
                initialVisible: initialVisible,
                initialWidth: initialWidth,
                openResult: openResult,
                shownAfterOpen: shownAfterOpen,
                closeResult: closeResult,
                shownAfterClose: shownAfterClose,
                actionReady: item.actionReady === true
            })
        }

        Component.onCompleted: {
            if (root.widgetSource !== "")
                setSource(root.widgetSource, {panelOverride: fakePanel})
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

    function writeResult(value) {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    Timer {
        interval: 1200
        running: true
        repeat: false
        onTriggered: if (!root.finished) root.writeResult({loaded: false})
    }
}
