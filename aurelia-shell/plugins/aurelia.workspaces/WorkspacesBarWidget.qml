import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../theme"
import "WorkspaceActionModel.js" as WorkspaceActionModel

Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.workspaces"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text

    // The current Aurelia bar is horizontal, but keeping the widget's
    // cross-axis contract here makes it compatible with a vertical bar host
    // without changing the workspace model or click behavior.
    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    readonly property int barSize: root.bar && root.bar.barSize ? root.bar.barSize : 26
    readonly property real trailingGap: root.vertical ? 0 : Theme.spacingXs / 2

    implicitWidth: workspaceGrid.implicitWidth + root.trailingGap
    // In a vertical bar the five workspace cells form the widget's actual
    // height. Reporting only one barSize made BarWidgetSlot clip the grid to a
    // single cell, so workspaces 1–5 disappeared below the first slot.
    implicitHeight: workspaceGrid.implicitHeight

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
        if (!root.validWorkspaceId(id)) {
            console.error("[WORKSPACES] click_failed reason=invalid_workspace id=" + String(id || ""))
            return "invalid-workspace"
        }
        var workspace = root.workspaceById(id)
        var action = WorkspaceActionModel.actionFor(workspace, id, Hyprland.usingLua)
        if (!action.ok) {
            console.error("[WORKSPACES] click_failed reason=" + action.reason +
                " id=" + String(id || ""))
            return action.reason
        }
        if (action.mode === "object") {
            try {
                workspace.activate()
                console.info("[WORKSPACES] click_dispatched id=" + action.id + " mode=object")
                return "ok"
            } catch (error) {
                console.error("[WORKSPACES] click_failed id=" + action.id +
                    " mode=object reason=activation_exception")
                return "error"
            }
        }

        // Empty baseline workspaces do not have a live object to activate.
        // Quickshell owns the Hyprland IPC connection for this fallback.
        try {
            Hyprland.dispatch(action.command)
            console.info("[WORKSPACES] click_dispatched id=" + action.id + " mode=dispatch")
            return "ok"
        } catch (error2) {
            console.error("[WORKSPACES] click_failed id=" + action.id +
                " mode=dispatch reason=dispatch_exception")
            return "error"
        }
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
                    color: root.barForeground
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
