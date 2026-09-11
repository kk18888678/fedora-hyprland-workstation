import QtQuick
import QtQuick.Layouts
import "../../theme"
import "."

// Preview-first workspace thumbnail. The workspace number and window count
// float above the captured content so the card stays useful without a second
// header/footer frame competing with the preview.
Item {
    id: root

    property int workspaceId: 1
    property var workspace: null
    property bool selected: false
    property bool focused: false
    property bool pointerHovered: false
    property bool previewActive: false
    property int modelRevision: 0

    signal activated()
    signal hovered()

    readonly property int windowCount: {
        var revision = root.modelRevision
        var values = root.workspace && root.workspace.toplevels
            ? root.workspace.toplevels.values
            : []
        return values ? values.length : 0
    }
    readonly property int shownWindowCount: Math.min(root.windowCount, 4)
    readonly property var previewWindows: {
        var revision = root.modelRevision
        var values = root.workspace && root.workspace.toplevels
            ? root.workspace.toplevels.values
            : []
        var result = []
        if (!values) return result
        for (var i = 0; i < values.length && i < 4; i++) result.push(values[i])
        return result
    }

    implicitWidth: 340
    implicitHeight: 216
    scale: root.selected ? 1.02 : 1.0

    Behavior on scale {
        NumberAnimation {
            duration: Theme.durationNormal
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: cardSurface
        anchors.fill: parent
        radius: Theme.radiusLg
        color: root.selected || root.pointerHovered
            ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.96)
            : Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b, 0.78)
        border.color: root.selected
            ? Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.48)
            : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.42)
        border.width: Theme.borderWidthDefault
        clip: true

        Rectangle {
            id: previewFrame
            anchors.fill: parent
            radius: Theme.radiusLg
            color: Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b, 0.52)
            clip: true

            GridLayout {
                anchors.fill: parent
                anchors.margins: 3
                columns: root.windowCount > 1 ? 2 : 1
                rows: Math.max(1, Math.ceil(root.shownWindowCount / (root.windowCount > 1 ? 2 : 1)))
                columnSpacing: Theme.spacingXs
                rowSpacing: Theme.spacingXs
                visible: root.selected || root.windowCount > 0

                Repeater {
                    model: root.previewWindows

                    delegate: WindowPreview {
                        required property var modelData

                        hyprlandToplevel: modelData
                        active: root.previewActive
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 1
                        Layout.minimumHeight: 1
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: "Empty"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                visible: root.windowCount === 0
            }

            Rectangle {
                id: workspaceBadge
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.spacingSm
                width: badgeLabel.implicitWidth + Theme.spacingMd * 2
                height: 26
                radius: height / 2
                color: root.focused || root.selected
                    ? Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b, 0.86)
                    : Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b, 0.72)
                border.color: root.selected
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.76)
                    : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.46)
                border.width: Theme.borderWidthDefault

                Text {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: root.focused ? "Current" : String(root.workspaceId)
                    color: root.focused || root.selected ? Theme.accent : Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightMedium
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingSm
                width: statusLabel.implicitWidth + Theme.spacingMd * 2
                height: 26
                radius: height / 2
                color: root.selected
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                    : Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b, 0.72)
                border.color: root.selected
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.88)
                    : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.46)
                border.width: Theme.borderWidthDefault
                visible: root.selected || root.windowCount > 0

                Text {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: root.selected
                        ? "Selected"
                        : (root.windowCount === 1 ? "1 window" : String(root.windowCount) + " windows")
                    color: root.selected ? Theme.accent : Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }
            }

            Rectangle {
                id: selectionRing
                anchors.fill: parent
                anchors.margins: 3
                radius: Math.max(0, Theme.radiusLg - 3)
                color: "transparent"
                border.color: Theme.accent
                border.width: 2
                visible: root.selected
                z: 10
            }

        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: function(mouse) { mouse.accepted = true }
            onEntered: {
                root.pointerHovered = true
                root.hovered()
            }
            onExited: root.pointerHovered = false
            onClicked: function(mouse) {
                mouse.accepted = true
                root.activated()
            }
        }
    }
}
