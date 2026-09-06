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

    implicitWidth: rowLayout.implicitWidth
    implicitHeight: bar ? bar.barSize : 38
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

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        spacing: Theme.spacingXs

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
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: root.implicitHeight
            }
        }
    }

}
