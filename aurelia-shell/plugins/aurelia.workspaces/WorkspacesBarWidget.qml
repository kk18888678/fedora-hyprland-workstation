import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../theme"

Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.workspaces"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null

    // The current Aurelia bar is horizontal, but keeping the widget's
    // cross-axis contract here makes it compatible with a vertical bar host
    // without changing the workspace model or click behavior.
    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    readonly property int barSize: root.bar && root.bar.barSize ? root.bar.barSize : 26
    readonly property real trailingGap: root.vertical ? 0 : Theme.spacingXs / 2

    implicitWidth: workspaceGrid.implicitWidth + root.trailingGap
    implicitHeight: root.barSize

    function workspaceValues() {
        return Hyprland.workspaces ? Hyprland.workspaces.values : []
    }

    function workspaceById(id) {
        var values = root.workspaceValues()
        for (var i = 0; i < values.length; i++) {
            if (values[i].id === id) return values[i]
        }
        return null
    }

    function workspaceIds() {
        var ids = [1, 2, 3, 4, 5]
        var values = root.workspaceValues()

        for (var i = 0; i < values.length; i++) {
            var id = values[i].id
            if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
        }

        ids.sort(function(left, right) { return left - right })
        return ids
    }

    function validWorkspaceId(value) {
        var id = Number(value)
        return isFinite(id) && Math.floor(id) === id && id >= 1 && id <= 10
    }

    function focusWorkspace(id) {
        if (!root.validWorkspaceId(id)) return false
        // Quickshell already owns the Hyprland IPC connection. Dispatching
        // through it avoids depending on HYPRLAND_INSTANCE_SIGNATURE being
        // exported to a child process and still accepts only normalized IDs.
        var workspaceId = String(Number(id))
        if (Hyprland.usingLua) {
            Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + workspaceId + "\" })")
        } else {
            Hyprland.dispatch("workspace " + workspaceId)
        }
        return true
    }

    GridLayout {
        id: workspaceGrid
        anchors.fill: parent
        anchors.rightMargin: root.trailingGap
        columns: root.vertical ? 1 : root.workspaceIds().length
        columnSpacing: root.vertical ? 0 : 1
        rowSpacing: root.vertical ? 2 : 0

        Repeater {
            model: root.workspaceIds()

            // Match Omarchy's WidgetButton: workspace entries are transparent
            // bar slots, not full-height cards. A card-sized Rectangle here
            // touches both bar edges and makes the numbers look like they are
            // breaking out of the bar.
            delegate: Item {
                required property int modelData

                readonly property var workspace: root.workspaceById(modelData)
                readonly property bool occupied: workspace !== null &&
                    workspace.toplevels && workspace.toplevels.values.length > 0
                readonly property bool focused: Hyprland.focusedWorkspace !== null &&
                    Hyprland.focusedWorkspace.id === modelData

                Layout.preferredWidth: root.vertical ? root.barSize : Theme.bar.workspaceWidth
                Layout.preferredHeight: root.barSize
                clip: true
                opacity: occupied || focused ? 1 : 0.5

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.durationFast
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    id: workspaceLabel
                    anchors.fill: parent
                    anchors.margins: 1
                    textFormat: Text.PlainText
                    text: focused ? "\uDB85\uDCFB" : (occupied ? (modelData === 10 ? "0" : String(modelData)) : "•")
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: !focused && !occupied
                        ? (root.bar && root.bar.barTextSize ? root.bar.barTextSize + 5 : Theme.fontSizeSm + 5)
                        : (root.bar && root.bar.barTextSize ? root.bar.barTextSize : Theme.fontSizeSm)
                    font.weight: Theme.fontWeightMedium
                    renderType: Text.NativeRendering
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.NoWrap
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        root.focusWorkspace(modelData)
                    }
                }
            }
        }
    }
}
