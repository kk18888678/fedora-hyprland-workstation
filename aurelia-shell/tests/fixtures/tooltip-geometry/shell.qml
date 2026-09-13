import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// T33 isolated mapping fixture. A FocusScope models the window content target
// that exposed the production warning; the source Item owns the conversion.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_TOOLTIP_GEOMETRY_RESULT") || ""
    property bool finished: false
    readonly property string tooltipSource: Quickshell.env("AURELIA_TOOLTIP_GEOMETRY_TOOLTIP_SOURCE") || ""
    readonly property string popupSource: Quickshell.env("AURELIA_TOOLTIP_GEOMETRY_POPUP_SOURCE") || ""
    property bool tooltipLoaded: false
    property bool popupLoaded: false

    FocusScope {
        id: contentScope
        objectName: "tooltip-geometry-content-scope"
        x: 37
        y: 19
        width: 640
        height: 64

        Item {
            id: sourceItem
            objectName: "tooltip-geometry-source-item"
            x: 121
            y: 7
            width: 24
            height: 20
        }
    }

    PanelWindow {
        id: barWindow
        visible: false
        width: 640
        height: 64
        anchors.top: true
        anchors.left: true
        anchors.right: true

        Item {
            id: panelSourceItem
            x: 121
            y: 7
            width: 24
            height: 20
        }
    }

    Loader {
        id: tooltipLoader
        active: root.tooltipSource !== ""
        source: root.tooltipSource
        onLoaded: root.tooltipLoaded = item !== null
    }

    Loader {
        id: popupLoader
        active: root.popupSource !== ""
        source: root.popupSource
        onLoaded: root.popupLoaded = item !== null
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

    function writeResult() {
        if (root.finished || root.resultPath === "") return
        root.finished = true
        var point = sourceItem.mapToItem(contentScope, sourceItem.width / 2, sourceItem.height + 6)
        var panelPoint = barWindow.mapFromItem(panelSourceItem, panelSourceItem.width / 2, panelSourceItem.height + 6)
        resultFile.setText(JSON.stringify({
            sourceHasMapToItem: typeof sourceItem.mapToItem === "function",
            anchorType: String(contentScope),
            panelContentType: String(barWindow.contentItem),
            panelHasMapFromItem: typeof barWindow.mapFromItem === "function",
            panelMappedX: panelPoint.x,
            panelMappedY: panelPoint.y,
            tooltipLoaded: root.tooltipLoaded,
            popupLoaded: root.popupLoaded,
            mappedX: point.x,
            mappedY: point.y,
            mappedFinite: isFinite(point.x) && isFinite(point.y),
            expectedX: sourceItem.x + sourceItem.width / 2,
            expectedY: sourceItem.y + sourceItem.height + 6
        }) + "\n")
    }

    Timer {
        interval: 250
        running: true
        repeat: false
        onTriggered: root.writeResult()
    }
}
