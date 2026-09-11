import QtQuick
import QtQuick.Layouts
import "../../theme"

// Renders one configured bar region. Unknown, disabled, or malformed widget
// ids collapse to zero width through BarWidgetSlot and never break the bar.
Item {
    id: root

    property var entries: []
    property var bar: null
    property var shell: null
    property var pluginRegistry: null
    property string aureliaPath: ""

    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    readonly property int barSize: root.bar && root.bar.barSize ? root.bar.barSize : 26

    implicitWidth: root.vertical ? root.barSize : gridLayout.implicitWidth
    implicitHeight: root.vertical ? gridLayout.implicitHeight : root.barSize
    width: implicitWidth
    height: implicitHeight

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

    GridLayout {
        id: gridLayout
        anchors.fill: parent
        columns: root.vertical ? 1 : Math.max(1, root.entries.length)
        columnSpacing: root.vertical ? 0 : Theme.spacingXs
        rowSpacing: root.vertical ? Theme.spacingXs : 0

        Repeater {
            model: root.entries

            delegate: BarWidgetSlot {
                required property var modelData
                pluginId: root.entryId(modelData)
                settings: root.entrySettings(modelData)
                bar: root.bar
                shell: root.shell
                pluginRegistry: root.pluginRegistry
                aureliaPath: root.aureliaPath
                Layout.preferredWidth: root.vertical ? root.barSize : implicitWidth
                Layout.preferredHeight: root.vertical ? implicitHeight : root.barSize
            }
        }
    }

}
