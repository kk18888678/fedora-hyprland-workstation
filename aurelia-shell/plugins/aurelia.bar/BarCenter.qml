import QtQuick
import "../../theme"

// The center region supports Omarchy's centerAnchor contract. Without an
// anchor the configured widgets are centered as a group; with one, the named
// widget stays at the exact center and its siblings flank it.
Item {
    id: root

    property var entries: []
    property string anchorId: ""
    property var bar: null
    property var shell: null
    property var pluginRegistry: null
    property string aureliaPath: ""

    implicitHeight: bar ? bar.barSize : 38

    function entryId(entry) {
        if (typeof entry === "string") return entry
        return entry && typeof entry.id === "string" ? entry.id : ""
    }

    function entrySettings(entry) {
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
        entries: root.entries
        bar: root.bar
        shell: root.shell
        pluginRegistry: root.pluginRegistry
        aureliaPath: root.aureliaPath
        width: implicitWidth
        height: implicitHeight
    }

    BarWidgetRow {
        id: beforeGroup
        anchors.right: centerAnchor.left
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasAnchor
        entries: root.beforeEntries
        bar: root.bar
        shell: root.shell
        pluginRegistry: root.pluginRegistry
        aureliaPath: root.aureliaPath
    }

    BarWidgetSlot {
        id: centerAnchor
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasAnchor
        pluginId: root.hasAnchor ? root.entryId(root.anchorEntry) : ""
        settings: root.hasAnchor ? root.entrySettings(root.anchorEntry) : ({})
        bar: root.bar
        shell: root.shell
        pluginRegistry: root.pluginRegistry
        aureliaPath: root.aureliaPath
    }

    BarWidgetRow {
        id: afterGroup
        anchors.left: centerAnchor.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.hasAnchor
        entries: root.afterEntries
        bar: root.bar
        shell: root.shell
        pluginRegistry: root.pluginRegistry
        aureliaPath: root.aureliaPath
    }

}
