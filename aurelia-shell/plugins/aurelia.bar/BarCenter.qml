import QtQuick
import "../../theme"
import "."

// The center region supports Omarchy's centerAnchor contract. Without an
// anchor the configured widgets are centered as a group; with one, the named
// widget stays at the exact center and its siblings flank it.
Item {
    id: root

    property var entries: []
    property string anchorId: ""
    property var bar: null
    property var barPanel: null
    property var shell: null
    property var pluginRegistry: null
    property var barWidgetRegistry: null
    property var pluginHost: null
    property string aureliaPath: ""

    // Empty center space owns Omarchy's direct bar-position and transparency
    // gestures. Child widget slots remain above this area and retain their own
    // click/wheel handlers.
    MouseArea {
        id: centerGesture
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton
        pressAndHoldInterval: 200
        propagateComposedEvents: true
        property bool dragging: false
        property bool suppressClick: false
        property real pressedX: 0
        property real pressedY: 0

        function startDrag(x, y) {
            if (root.barPanel && typeof root.barPanel.beginBarMove === "function") {
                dragging = true
                root.barPanel.beginBarMove()
                root.barPanel.updateBarMove(root.bar.screenPointFromItem(
                    centerGesture, x, y, root.barPanel))
            }
        }

        onPressed: function(mouse) {
            dragging = false
            suppressClick = false
            pressedX = mouse.x
            pressedY = mouse.y
        }

        onPressAndHold: function(mouse) {
            if (centerGesture.pressed) centerGesture.startDrag(mouse.x, mouse.y)
        }

        onPositionChanged: function(mouse) {
            if (!(mouse.buttons & Qt.LeftButton)) return
            if (!dragging) {
                var threshold = root.bar && root.bar.barDragThreshold !== undefined
                    ? Number(root.bar.barDragThreshold) : 4
                var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
                if (distance < threshold) return
                centerGesture.startDrag(mouse.x, mouse.y)
            }
            if (dragging && root.barPanel && typeof root.barPanel.updateBarMove === "function")
                root.barPanel.updateBarMove(root.bar.screenPointFromItem(
                    centerGesture, mouse.x, mouse.y, root.barPanel))
        }

        onReleased: function(mouse) {
            if (!dragging) {
                mouse.accepted = false
                return
            }
            dragging = false
            suppressClick = true
            if (root.barPanel && typeof root.barPanel.finishBarMove === "function")
                root.barPanel.finishBarMove()
            mouse.accepted = true
        }

        onCanceled: {
            dragging = false
            suppressClick = false
            if (root.barPanel && typeof root.barPanel.clearBarMove === "function")
                root.barPanel.clearBarMove()
        }

        onClicked: function(mouse) {
            if (suppressClick) {
                suppressClick = false
                mouse.accepted = true
            }
        }

        onDoubleClicked: function(mouse) {
            if (suppressClick) {
                suppressClick = false
                return
            }
            if (root.bar && typeof root.bar.toggleTransparency === "function") {
                root.bar.toggleTransparency()
                mouse.accepted = true
            }
        }
    }

    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    readonly property int barSize: root.bar && root.bar.barSize ? root.bar.barSize : 26

    implicitWidth: root.vertical ? root.barSize : parent ? parent.width : root.barSize
    implicitHeight: root.vertical ? (centerAnchor.implicitHeight || root.barSize) : root.barSize

    function entryId(entry) {
        if (typeof entry === "string") return entry
        return entry && typeof entry.id === "string" ? entry.id : ""
    }

    function entrySettings(entry) {
        var id = root.entryId(entry)
        if (root.barWidgetRegistry && typeof root.barWidgetRegistry.settingsFor === "function")
            return root.barWidgetRegistry.settingsFor(id, entry)
        if (!entry || typeof entry !== "object" || Array.isArray(entry)) return {}
        var result = {}
        for (var key in entry) {
            if (key !== "id" && key !== "settings") result[key] = entry[key]
        }
        if (entry.settings && typeof entry.settings === "object" && !Array.isArray(entry.settings)) {
            for (var nestedKey in entry.settings) {
                if (result[nestedKey] === undefined) result[nestedKey] = entry.settings[nestedKey]
            }
        }
        return result
    }

    function entryInstanceId(entry) {
        var id = root.entryId(entry)
        if (root.barWidgetRegistry && typeof root.barWidgetRegistry.instanceIdFor === "function")
            return root.barWidgetRegistry.instanceIdFor(id, entry)
        return id
    }

    function anchorIndex() {
        for (var i = 0; i < root.entries.length; i++) {
            if (root.entryId(root.entries[i]) === root.anchorId) return i
        }
        return -1
    }

    readonly property bool hasAnchor: root.anchorId !== "" && root.anchorIndex() >= 0
    readonly property var anchorEntry: root.hasAnchor ? root.entries[root.anchorIndex()] : ({})
    readonly property var beforeEntries: root.hasAnchor ? root.entries.slice(0, root.anchorIndex()) : []
    readonly property var afterEntries: root.hasAnchor ? root.entries.slice(root.anchorIndex() + 1) : []

    BarWidgetRow {
        id: centeredGroup
        anchors.centerIn: parent
        visible: !root.hasAnchor
        // `visible: false` does not destroy a QML row or its Loader delegates.
        // Do not instantiate a second copy of every widget when an exact
        // center anchor is active; the before/anchor/after rows own those
        // entries in that mode.
        entries: root.hasAnchor ? [] : root.entries
        bar: root.bar
        barPanel: root.barPanel
        shell: root.shell
        pluginRegistry: root.pluginRegistry
        barWidgetRegistry: root.barWidgetRegistry
        pluginHost: root.pluginHost
        aureliaPath: root.aureliaPath
        region: "center"
        width: implicitWidth
        height: implicitHeight
    }

    BarWidgetRow {
        id: beforeGroup
        anchors.right: root.vertical ? undefined : centerAnchor.left
        anchors.bottom: root.vertical ? centerAnchor.top : undefined
        anchors.horizontalCenter: root.vertical ? centerAnchor.horizontalCenter : undefined
        anchors.verticalCenter: root.vertical ? undefined : centerAnchor.verticalCenter
        visible: root.hasAnchor
        entries: root.beforeEntries
        bar: root.bar
        barPanel: root.barPanel
        shell: root.shell
        pluginRegistry: root.pluginRegistry
        barWidgetRegistry: root.barWidgetRegistry
        pluginHost: root.pluginHost
        aureliaPath: root.aureliaPath
        region: "center"
    }

    BarWidgetSlot {
        id: centerAnchor
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasAnchor
        pluginId: root.hasAnchor ? root.entryId(root.anchorEntry) : ""
        instanceId: root.hasAnchor ? root.entryInstanceId(root.anchorEntry) : ""
        settings: root.hasAnchor ? root.entrySettings(root.anchorEntry) : ({})
        bar: root.bar
        barPanel: root.barPanel
        shell: root.shell
        pluginRegistry: root.pluginRegistry
        barWidgetRegistry: root.barWidgetRegistry
        pluginHost: root.pluginHost
        aureliaPath: root.aureliaPath
        region: "center"
    }

    BarWidgetRow {
        id: afterGroup
        anchors.left: root.vertical ? undefined : centerAnchor.right
        anchors.top: root.vertical ? centerAnchor.bottom : undefined
        anchors.horizontalCenter: root.vertical ? centerAnchor.horizontalCenter : undefined
        anchors.verticalCenter: root.vertical ? undefined : centerAnchor.verticalCenter
        visible: root.hasAnchor
        entries: root.afterEntries
        bar: root.bar
        barPanel: root.barPanel
        shell: root.shell
        pluginRegistry: root.pluginRegistry
        barWidgetRegistry: root.barWidgetRegistry
        pluginHost: root.pluginHost
        aureliaPath: root.aureliaPath
        region: "center"
    }

}
