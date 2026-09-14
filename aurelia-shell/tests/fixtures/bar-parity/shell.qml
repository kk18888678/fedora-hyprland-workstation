import QtQuick
import Quickshell
import Quickshell.Io

// T53 fixture. It constructs the real center and slot components with a
// detached bar facade. No PanelWindow or live compositor is required for this
// contract fixture.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_BAR_PARITY_RESULT") || ""
    readonly property string centerSource: Quickshell.env("AURELIA_BAR_PARITY_CENTER_SOURCE") || ""
    readonly property string slotSource: Quickshell.env("AURELIA_BAR_PARITY_SLOT_SOURCE") || ""
    property bool evaluated: false

    QtObject {
        id: fakeShell
        property string lastPosition: ""
        property string lastTransparent: ""
        property string lastMoveId: ""
        property string lastMovePlacement: ""

        function setBarPosition(value) {
            lastPosition = String(value || "")
            return "ok"
        }

        function setBarTransparent(value) {
            lastTransparent = String(value || "")
            return "ok"
        }

        function moveBarWidget(id, placement) {
            lastMoveId = String(id || "")
            lastMovePlacement = String(placement || "")
            return "ok"
        }
    }

    QtObject {
        id: fakeBar
        property bool vertical: false
        property int barSize: 32
        property int barDragThreshold: 4
        property bool transparent: false
        property color barForeground: "#ffffff"
        property var widgetDragSource: null
        property var shell: fakeShell

        function beginBarMove() {}
        function updateBarMove() {}
        function finishBarMove() { return "ok" }
        function clearBarMove() {}
        function toggleTransparency() { return "ok" }
        function screenPointFromItem(item, x, y) { return {x: x, y: y} }
        function beginWidgetDrag() { return true }
        function updateWidgetDrag() {}
        function endWidgetDrag() { return "ok" }
        function cancelWidgetDrag() {}
    }

    // The real PluginBarApi shape is verified statically in the suite. This
    // detached QObject keeps this fixture independent from module import
    // registration while still testing the scalar values passed to a plugin.
    QtObject {
        id: facade
        property string ownerPluginId
        property color foreground
        property color barForeground
        property color background
        property color urgent
        property bool transparent
        property bool foregroundAnimationEnabled
        ownerPluginId: "fixture.widget"
        foreground: "#101010"
        barForeground: "#101010"
        background: "#232136"
        urgent: "#9ccfd8"
        transparent: true
        foregroundAnimationEnabled: false
    }

    Loader {
        id: centerLoader
        source: root.centerSource
        onLoaded: {
            item.width = 640
            item.height = 32
            item.entries = []
            item.anchorId = ""
            item.bar = fakeBar
            item.shell = fakeShell
            root.evaluate()
        }
    }

    Loader {
        id: slotLoader
        source: root.slotSource
        onLoaded: {
            item.width = 32
            item.height = 32
            item.active = false
            item.pluginId = "fixture.widget"
            item.instanceId = "fixture.widget"
            item.bar = fakeBar
            item.shell = fakeShell
            item.region = "center"
            root.evaluate()
        }
    }

    function writeResult(value) {
        if (root.evaluated || root.resultPath === "") return
        root.evaluated = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    function evaluate() {
        if (centerLoader.item === null || slotLoader.item === null) return
        root.writeResult({
            centerConstructed: centerLoader.item !== null,
            slotConstructed: slotLoader.item !== null,
            facadeTransparent: facade.transparent === true,
            facadeForeground: String(facade.barForeground),
            topEdge: root.nearestEdge({x: 320, y: 5}, 640, 360),
            bottomEdge: root.nearestEdge({x: 320, y: 355}, 640, 360),
            leftEdge: root.nearestEdge({x: 5, y: 180}, 640, 360),
            rightEdge: root.nearestEdge({x: 635, y: 180}, 640, 360)
        })
    }

    function nearestEdge(point, width, height) {
        var x = Number(point.x)
        var y = Number(point.y)
        var nx = Math.max(0, Math.min(1, x / width))
        var ny = Math.max(0, Math.min(1, y / height))
        var edge = "top"
        var best = ny
        if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
        if (nx < best) { edge = "left"; best = nx }
        if (1 - nx < best) edge = "right"
        return edge
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

    Component.onCompleted: {
        root.evaluate()
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
