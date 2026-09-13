import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../../ui"
import "Model.js" as Model

// Battery-independent restoration of Aurelia's former session-action popup.
// Power owns battery/profile information; this plugin owns session lifecycle
// commands and remains available on desktops and VMs without a battery.
AureliaKeyboardPanel {
    id: root

    property var shell: null
    property string moduleName: "aurelia.session-actions"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
    property var actionExecutor
    property QtObject runtime: SessionActionsRuntime { owner: root }

    property string confirmAction: ""
    property bool actionRunning: false
    property string actionError: ""
    property int actionIndex: 0
    property bool cursorActive: false

    readonly property var actionRows: Model.actionRows()
    readonly property var visibleActionRows: root.confirmAction === ""
        ? root.actionRows : Model.confirmationRows(root.confirmAction)

    ownerId: "aurelia.session-actions"
    anchorItem: root.barAnchorItem
    popupWidth: 300
    popupHeight: 260
    fitHeightToContent: true
    minPopupHeight: 160
    maxPopupHeight: 320
    contentSizingItem: contentColumn
    focusTarget: keyScope
    shown: false

    function open(payloadJson) {
        root.confirmAction = ""
        root.actionError = ""
        root.actionIndex = 0
        root.cursorActive = false
        root.shown = true
        return "ok"
    }

    function close() {
        root.confirmAction = ""
        root.actionIndex = 0
        root.cursorActive = false
        root.shown = false
        return "ok"
    }

    function closeForPopoutSwitch() { return root.close() }

    function requestAction(action) {
        var requested = String(action || "")
        if (!Model.isKnownAction(requested)) return "invalid"
        if (Model.requiresConfirmation(requested)) {
            root.confirmAction = requested
            root.actionIndex = 0
            root.cursorActive = false
            return "confirm"
        }
        return root.runAction(requested)
    }

    function runAction(action) {
        var requested = String(action || "")
        var command = Model.commandFor(requested)
        if (command.length === 0) return "invalid"
        var result = root.runtime.runCommand(command, requested)
        if (result === "ok" || result === "pending") root.close()
        return result
    }

    function confirmPendingAction() {
        if (!Model.requiresConfirmation(root.confirmAction)) return "invalid"
        return root.runAction(root.confirmAction)
    }

    function cancelPendingAction() {
        root.confirmAction = ""
        root.actionIndex = 0
        root.cursorActive = false
        return "ok"
    }

    function moveSelection(delta) {
        var rows = root.visibleActionRows
        if (!Array.isArray(rows) || rows.length === 0) return
        root.actionIndex = Math.max(0, Math.min(rows.length - 1, root.actionIndex + delta))
        root.cursorActive = true
    }

    function activateSelection() {
        var rows = root.visibleActionRows
        if (!Array.isArray(rows) || root.actionIndex < 0 || root.actionIndex >= rows.length) return "invalid"
        var selected = rows[root.actionIndex]
        if (root.confirmAction !== "")
            return selected.id === "confirm" ? root.confirmPendingAction() : root.cancelPendingAction()
        return root.requestAction(selected.id)
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            root.moveSelection(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            root.moveSelection(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activateSelection()
            event.accepted = true
        }
    }

    onShownChanged: {
        if (root.shown) {
            root.actionIndex = 0
            root.cursorActive = false
            Qt.callLater(function() {
                if (root.shown && keyScope && typeof keyScope.forceActiveFocus === "function")
                    keyScope.forceActiveFocus()
            })
        }
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: root.shown
        Keys.onPressed: function(event) { root.handleKey(event) }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            spacing: Theme.spacingXs

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXs

                AureliaIcon {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    iconSize: 18
                    name: "system-shutdown"
                    fallbackName: "system-power-off"
                    tint: Theme.accent
                }

                Text {
                    Layout.fillWidth: true
                    text: root.confirmAction === "" ? "Session actions" :
                        (root.confirmAction === "reboot" ? "Restart computer?" : "Power off computer?")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMd
                    font.weight: Theme.fontWeightMedium
                    elide: Text.ElideRight
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.confirmAction === "" ? "" : "This action changes the current session."
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                visible: root.confirmAction !== ""
                elide: Text.ElideRight
            }

            GridLayout {
                id: actionGrid
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.spacingXs
                rowSpacing: Theme.spacingXs

                Repeater {
                    model: root.visibleActionRows

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        radius: Theme.radiusSm
                        color: root.cursorActive && root.actionIndex === index
                            ? Theme.selectionActive
                            : (actionHover.hovered ? Theme.selection : "transparent")
                        border.color: root.cursorActive && root.actionIndex === index
                            ? Theme.borderActive : (actionHover.hovered ? Theme.border : "transparent")
                        border.width: Theme.borderWidthDefault
                        opacity: root.actionRunning ? 0.55 : 1.0

                        HoverHandler { id: actionHover }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSm
                            anchors.rightMargin: Theme.spacingSm
                            spacing: Theme.spacingXs

                            AureliaIcon {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                iconSize: 17
                                glyph: modelData.glyph
                                tint: root.cursorActive && root.actionIndex === index
                                    ? Theme.accent : Theme.textSecondary
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Theme.fontWeightMedium
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.actionRunning
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                root.cursorActive = true
                                root.actionIndex = index
                            }
                            onClicked: {
                                mouse.accepted = true
                                if (root.confirmAction !== "") {
                                    if (modelData.id === "confirm") root.confirmPendingAction()
                                    else root.cancelPendingAction()
                                } else {
                                    root.requestAction(modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.actionError !== ""
                text: root.actionError
                color: Theme.warning
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                elide: Text.ElideRight
            }
        }
    }
}
