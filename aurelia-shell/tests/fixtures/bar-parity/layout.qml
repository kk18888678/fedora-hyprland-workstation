import QtQuick
import Quickshell
import Quickshell.Io

// T54 orientation fixture. It loads the real BarWidgetRow/BarWidgetSlot
// components with deterministic first-party widget descriptors, then changes
// the real vertical binding and verifies that every slot stays in-bounds.
ShellRoot {
    id: root

    readonly property string rowSource: Quickshell.env("AURELIA_BAR_LAYOUT_ROW_SOURCE") || ""
    readonly property string widgetSource: Quickshell.env("AURELIA_BAR_LAYOUT_WIDGET_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_LAYOUT_RESULT") || ""
    property bool evaluated: false
    property bool rowActive: true
    property var row: null

    QtObject {
        id: fakeBar
        property bool vertical: false
        property int barSize: 32
        property int barDragThreshold: 4
        property bool transparent: false
        property color barForeground: "#ffffff"
        property string activePopoutId: ""
        property var widgetDragSource: null
        property var slots: []

        function registerWidgetSlot(slot) {
            if (slots.indexOf(slot) === -1) slots = slots.concat([slot])
        }

        function unregisterWidgetSlot(slot) {
            slots = slots.filter(function(item) { return item !== slot })
        }

        function bumpWidgetRevision() {}
        function beginWidgetDrag() { return false }
    }

    QtObject {
        id: fakeRegistry
        property int registryRevision: 1
        property int runtimeFailureRevision: 0
        signal localPluginChanged(string changedPluginId)

        function hasWidget(id) { return id === "fixture.one" || id === "fixture.two" }
        function manifestFor(id) {
            return hasWidget(id) ? {kinds: ["bar-widget"], __isFirstParty: true} : null
        }
        function sourceDescriptorFor(id) {
            return hasWidget(id) ? {
                valid: true,
                id: id,
                kind: "bar-widget",
                sourceRoot: "",
                relativeEntryPoint: "widget.qml",
                sourcePath: root.widgetSource,
                url: root.widgetSource
            } : {valid: false, url: ""}
        }
        function settingsFor(id, entry) { return {} }
        function instanceIdFor(id, entry) { return id }
        function isEnabled(id) { return hasWidget(id) }
        function hasActiveRuntimeFailure() { return false }
    }

    QtObject {
        id: fakeHost
        function configurePluginTarget() {}
    }

    Loader {
        id: rowLoader
        active: root.rowActive
        source: root.rowSource
        onLoaded: {
            item.entries = [{id: "fixture.one"}, {id: "fixture.two"}]
            item.region = "right"
            item.bar = fakeBar
            item.pluginRegistry = fakeRegistry
            item.barWidgetRegistry = fakeRegistry
            item.pluginHost = fakeHost
            item.width = 300
            item.height = 32
            root.row = item
            root.waitForSlots()
        }
    }

    function allSlotsInBounds() {
        if (!root.row || fakeBar.slots.length !== 2) return false
        for (var i = 0; i < fakeBar.slots.length; i++) {
            var slot = fakeBar.slots[i]
            if (!slot || !slot.visible || slot.width <= 0 || slot.height <= 0) return false
            if (slot.x < -0.5 || slot.y < -0.5 ||
                slot.x + slot.width > root.row.width + 0.5 ||
                slot.y + slot.height > root.row.height + 0.5) return false
        }
        return true
    }

    function waitForSlots() {
        if (root.evaluated) return
        if (!root.row || fakeBar.slots.length !== 2) {
            slotTimer.restart()
            return
        }
        horizontalInBounds = root.allSlotsInBounds()
        fakeBar.vertical = true
        root.row.width = 32
        root.row.height = 64
        verticalTimer.restart()
    }

    function finish() {
        if (root.evaluated) return
        root.evaluated = true
        resultFile.setText(JSON.stringify({
            horizontalInBounds: horizontalInBounds,
            verticalInBounds: verticalInBounds,
            restoredInBounds: restoredInBounds,
            verticalWidthsFit: verticalWidthsFit,
            horizontalWidthsRestored: horizontalWidthsRestored,
            recreatedInBounds: recreatedInBounds
        }) + "\n")
    }

    property bool horizontalInBounds: false
    property bool verticalInBounds: false
    property bool restoredInBounds: false
    property bool verticalWidthsFit: false
    property bool horizontalWidthsRestored: false
    property bool recreatedInBounds: false

    Timer {
        id: slotTimer
        interval: 120
        repeat: false
        onTriggered: root.waitForSlots()
    }

    Timer {
        id: verticalTimer
        interval: 180
        repeat: false
        onTriggered: {
            root.verticalInBounds = root.allSlotsInBounds()
            root.verticalWidthsFit = fakeBar.slots.every(function(slot) {
                return Math.abs(slot.width - fakeBar.barSize) < 0.5
            })
            fakeBar.vertical = false
            root.row.width = 300
            root.row.height = 32
            horizontalTimer.restart()
        }
    }

    Timer {
        id: horizontalTimer
        interval: 180
        repeat: false
        onTriggered: {
            root.restoredInBounds = root.allSlotsInBounds()
            root.horizontalWidthsRestored = fakeBar.slots.every(function(slot) {
                return slot.width > fakeBar.barSize
            })
            root.row = null
            root.rowActive = false
            recreateTimer.restart()
        }
    }

    Timer {
        id: recreateTimer
        interval: 120
        repeat: false
        onTriggered: {
            root.rowActive = true
            recreateSettledTimer.restart()
        }
    }

    Timer {
        id: recreateSettledTimer
        interval: 220
        repeat: false
        onTriggered: {
            root.recreatedInBounds = root.allSlotsInBounds()
            root.finish()
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

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
