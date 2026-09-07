import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../theme"

PanelWindow {
    id: panelRoot

    property int barSize: anchorWindow ? anchorWindow.barSize : 26
    property var anchorWindow: null
    property date displayedMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    readonly property int year: displayedMonth.getFullYear()
    readonly property int month: displayedMonth.getMonth()
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
    readonly property int firstWeekday: new Date(year, month, 1).getDay()
    readonly property var dayCells: buildDayCells()
    readonly property var today: new Date()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-calendar"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitWidth: 0
    implicitHeight: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    readonly property bool barAtBottom: anchorWindow && anchorWindow.position === "bottom"
    readonly property int barTopClearance: anchorWindow && anchorWindow.surfaceTop !== undefined ? anchorWindow.surfaceTop + panelRoot.barSize : panelRoot.barSize
    readonly property int barBottomClearance: anchorWindow && anchorWindow.surfaceBottom !== undefined ? anchorWindow.surfaceBottom + panelRoot.barSize : panelRoot.barSize

    function open(payloadJson) {
        if (anchorWindow && typeof anchorWindow.refreshSurfaceGeometry === "function") anchorWindow.refreshSurfaceGeometry()
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot, "aurelia.clock")
        displayedMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1)
        visible = true
    }

    function close() {
        visible = false
        if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(panelRoot)
    }

    function closeForPopoutSwitch() { close() }

    function previousMonth() {
        displayedMonth = new Date(year, month - 1, 1)
    }

    function nextMonth() {
        displayedMonth = new Date(year, month + 1, 1)
    }

    function buildDayCells() {
        var result = []
        for (var blank = 0; blank < firstWeekday; blank++) result.push({ day: 0 })
        for (var day = 1; day <= daysInMonth; day++) result.push({ day: day })
        while (result.length % 7 !== 0) result.push({ day: 0 })
        return result
    }

    function monthTitle() {
        return Qt.formatDate(displayedMonth, "MMMM yyyy")
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton
        onClicked: function(mouse) {
            mouse.accepted = true
            panelRoot.close()
        }
    }

    Rectangle {
        id: card
        width: 360
        height: 350
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: barAtBottom ? undefined : parent.top
        anchors.bottom: barAtBottom ? parent.bottom : undefined
        anchors.topMargin: barAtBottom ? 0 : panelRoot.barTopClearance + Theme.spacingXl
        anchors.bottomMargin: barAtBottom ? panelRoot.barBottomClearance + Theme.spacingXl : 0
        radius: Theme.radiusLg
        color: Theme.bgBase
        border.color: Theme.border
        border.width: Theme.borderWidthDefault
        focus: panelRoot.visible

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: panelRoot.monthTitle()
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.weight: Theme.fontWeightBold
                }
                Text {
                    text: "ESC"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "‹"
                    color: Theme.accent
                    font.pixelSize: 26
                    MouseArea { anchors.fill: parent; onClicked: panelRoot.previousMonth() }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Today"
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    MouseArea {
                        anchors.fill: parent
                        onClicked: panelRoot.open("{}")
                    }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: "›"
                    color: Theme.accent
                    font.pixelSize: 26
                    MouseArea { anchors.fill: parent; onClicked: panelRoot.nextMonth() }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: Theme.spacingXs
                columnSpacing: Theme.spacingXs

                Repeater {
                    model: ["S", "M", "T", "W", "T", "F", "S"]
                    delegate: Text {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightMedium
                    }
                }

                Repeater {
                    model: panelRoot.dayCells
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusSm
                        color: modelData.day === 0 ? "transparent" : (modelData.day === panelRoot.today.getDate() && panelRoot.month === panelRoot.today.getMonth() && panelRoot.year === panelRoot.today.getFullYear() ? Theme.accent : Theme.surface)

                        Text {
                            anchors.centerIn: parent
                            text: modelData.day > 0 ? modelData.day : ""
                            color: modelData.day === panelRoot.today.getDate() && panelRoot.month === panelRoot.today.getMonth() && panelRoot.year === panelRoot.today.getFullYear() ? Theme.bgBase : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                panelRoot.close()
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                panelRoot.previousMonth()
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                panelRoot.nextMonth()
                event.accepted = true
            }
        }
    }
}
