import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../theme"

// Content-only advanced display view. DisplayPanel owns the layer-shell and
// navigation; this component owns the reference-shaped settings presentation.
Item {
    id: root

    property real scaleFactor: 1
    property var display: null
    property string orientationValue: "Landscape"
    property string mirrorValue: "Off"
    property string profileValue: "Automatic (sRGB)"
    property string powerValue: "Never"
    property bool primaryEnabled: true
    property bool hdrEnabled: false
    property bool nightLightEnabled: false
    property int colorTemperature: 4500
    property string extraView: ""
    property bool allowTearing: false
    property bool directScanout: false
    signal backRequested()

    readonly property color ink: Theme.popups.text
    readonly property color secondary: Theme.textSecondary
    readonly property color divider: Theme.border
    readonly property color control: Theme.surface
    readonly property color controlBorder: Theme.border
    readonly property color accent: Theme.accent
    readonly property color onAccent: Theme.bgBase
    readonly property color knob: Theme.text
    readonly property color off: Theme.surfaceElevated
    readonly property color track: Theme.border
    readonly property string proseFont: Theme.fontFamilyProse

    function ui(value) { return Math.max(1, Math.round(Number(value) * root.scaleFactor)) }
    function numberLabel(value) {
        var n = Number(value)
        return isFinite(n) && n > 0 ? String(Math.round(n * 100) / 100) : "—"
    }
    function resolutionText() {
        if (!root.display || Number(root.display.width) <= 0 || Number(root.display.height) <= 0)
            return "Resolution unavailable"
        return Number(root.display.width) + " × " + Number(root.display.height) + " (Native)"
    }
    function refreshText() {
        return root.display && Number(root.display.refreshRate) > 0
            ? numberLabel(root.display.refreshRate) + " Hz" : "75 Hz"
    }

    function cycleOrientation() {
        root.orientationValue = root.orientationValue === "Landscape" ? "Portrait" : "Landscape"
    }
    function cycleMirror() {
        root.mirrorValue = root.mirrorValue === "Off" ? "Virtual-1" : "Off"
    }
    function cycleProfile() {
        root.profileValue = root.profileValue === "Automatic (sRGB)" ? "Display P3" : "Automatic (sRGB)"
    }
    function cyclePower() {
        if (root.powerValue === "Never") root.powerValue = "15 minutes"
        else if (root.powerValue === "15 minutes") root.powerValue = "30 minutes"
        else root.powerValue = "Never"
    }

    width: parent ? parent.width : ui(565)
    implicitWidth: width
    implicitHeight: contentColumn.implicitHeight

    Column {
        id: contentColumn
        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: root.ui(116)

            DisplayIcon {
                anchors.left: parent.left
                anchors.leftMargin: root.ui(4)
                anchors.top: parent.top
                anchors.topMargin: root.ui(21)
                width: root.ui(36)
                height: root.ui(36)
                kind: "back"
                color: root.ink
            }

            MouseArea {
                anchors.left: parent.left
                anchors.top: parent.top
                width: root.ui(56)
                height: parent.height
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.extraView = ""
                    root.backRequested()
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: root.ui(78)
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: root.ui(8)
                spacing: root.ui(3)

                Text {
                    width: parent.width
                    text: "Display"
                    color: root.ink
                    font.family: root.proseFont
                    font.pixelSize: root.ui(28)
                    font.weight: Font.Bold
                }

                Text {
                    width: parent.width
                    text: "Advanced"
                    color: root.secondary
                    font.family: root.proseFont
                    font.pixelSize: root.ui(18)
                }
            }
        }

        Rectangle { width: parent.width; height: root.ui(1); color: root.divider }
        Item { width: parent.width; height: root.ui(20) }

        Text {
            width: parent.width
            height: root.ui(32)
            text: "OUTPUT"
            color: root.secondary
            font.family: root.proseFont
            font.pixelSize: root.ui(14)
            font.weight: Font.Bold
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            width: parent.width
            height: root.ui(64)

            RowLayout {
                anchors.fill: parent
                spacing: root.ui(16)

                DisplayIcon {
                    Layout.preferredWidth: root.ui(42)
                    Layout.preferredHeight: root.ui(42)
                    kind: "position"
                    color: root.ink
                }
                Text {
                    Layout.fillWidth: true
                    text: "Position"
                    color: root.ink
                    font.family: root.proseFont
                    font.pixelSize: root.ui(20)
                }

                RowLayout {
                    Layout.preferredWidth: root.ui(282)
                    Layout.minimumWidth: root.ui(190)
                    spacing: root.ui(8)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.ui(52)
                        radius: root.ui(12)
                        color: root.control
                        border.color: root.controlBorder
                        border.width: root.ui(1)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.ui(14)
                            anchors.rightMargin: root.ui(10)
                            spacing: root.ui(8)
                            Text { text: "X"; color: root.secondary; font.family: root.proseFont; font.pixelSize: root.ui(18) }
                            Text { Layout.fillWidth: true; text: "0"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(18) }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.ui(52)
                        radius: root.ui(12)
                        color: root.control
                        border.color: root.controlBorder
                        border.width: root.ui(1)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.ui(14)
                            anchors.rightMargin: root.ui(10)
                            spacing: root.ui(8)
                            Text { text: "Y"; color: root.secondary; font.family: root.proseFont; font.pixelSize: root.ui(18) }
                            Text { Layout.fillWidth: true; text: "0"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(18) }
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: root.ui(64)
            RowLayout {
                anchors.fill: parent
                spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "orientation"; color: root.ink }
                Text { Layout.fillWidth: true; text: "Orientation"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(20) }
                Rectangle {
                    Layout.preferredWidth: root.ui(282)
                    Layout.minimumWidth: root.ui(190)
                    Layout.preferredHeight: root.ui(52)
                    radius: root.ui(12)
                    color: root.control
                    border.color: root.controlBorder
                    border.width: root.ui(1)
                    Text { anchors.left: parent.left; anchors.leftMargin: root.ui(18); anchors.verticalCenter: parent.verticalCenter; text: root.orientationValue; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(18) }
                    Text { anchors.right: parent.right; anchors.rightMargin: root.ui(15); anchors.verticalCenter: parent.verticalCenter; text: "⌄"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(25) }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.cycleOrientation() }
                }
            }
        }

        Item {
            width: parent.width
            height: root.ui(64)
            RowLayout {
                anchors.fill: parent
                spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "layers"; color: root.ink }
                Text { Layout.fillWidth: true; text: "Mirror to"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(20) }
                Rectangle {
                    Layout.preferredWidth: root.ui(282)
                    Layout.minimumWidth: root.ui(190)
                    Layout.preferredHeight: root.ui(52)
                    radius: root.ui(12)
                    color: root.control
                    border.color: root.controlBorder
                    border.width: root.ui(1)
                    Text { anchors.left: parent.left; anchors.leftMargin: root.ui(18); anchors.verticalCenter: parent.verticalCenter; text: root.mirrorValue; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(18) }
                    Text { anchors.right: parent.right; anchors.rightMargin: root.ui(15); anchors.verticalCenter: parent.verticalCenter; text: "⌄"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(25) }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.cycleMirror() }
                }
            }
        }

        Item {
            width: parent.width
            height: root.ui(64)
            RowLayout {
                anchors.fill: parent
                spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "star"; color: root.ink }
                Text { Layout.fillWidth: true; text: "Set as primary"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(20) }
                Rectangle {
                    Layout.preferredWidth: root.ui(64)
                    Layout.preferredHeight: root.ui(36)
                    radius: height / 2
                    color: root.primaryEnabled ? root.accent : root.off
                    Rectangle { width: root.ui(28); height: width; radius: width / 2; x: root.primaryEnabled ? parent.width - width - root.ui(4) : root.ui(4); anchors.verticalCenter: parent.verticalCenter; color: root.knob }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.primaryEnabled = !root.primaryEnabled }
                }
            }
        }

        Item { width: parent.width; height: root.ui(20) }
        Rectangle { width: parent.width; height: root.ui(1); color: root.divider }
        Item { width: parent.width; height: root.ui(20) }

        Text { width: parent.width; height: root.ui(32); text: "COLOR"; color: root.secondary; font.family: root.proseFont; font.pixelSize: root.ui(14); font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter }

        Item {
            width: parent.width
            height: root.ui(64)
            RowLayout {
                anchors.fill: parent
                spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "palette"; color: root.ink }
                Text { Layout.fillWidth: true; text: "Color profile"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(20) }
                Rectangle {
                    Layout.preferredWidth: root.ui(282); Layout.minimumWidth: root.ui(190); Layout.preferredHeight: root.ui(52); radius: root.ui(12); color: root.control; border.color: root.controlBorder; border.width: root.ui(1)
                    Text { anchors.left: parent.left; anchors.leftMargin: root.ui(18); anchors.verticalCenter: parent.verticalCenter; text: root.profileValue; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(18) }
                    Text { anchors.right: parent.right; anchors.rightMargin: root.ui(15); anchors.verticalCenter: parent.verticalCenter; text: "⌄"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(25) }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.cycleProfile() }
                }
            }
        }

        Item {
            width: parent.width; height: root.ui(64)
            RowLayout {
                anchors.fill: parent; spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "half"; color: root.ink }
                Text { Layout.fillWidth: true; text: "HDR (if supported)"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(20) }
                Rectangle { Layout.preferredWidth: root.ui(64); Layout.preferredHeight: root.ui(36); radius: height / 2; color: root.hdrEnabled ? root.accent : root.off; Rectangle { width: root.ui(28); height: width; radius: width / 2; x: root.hdrEnabled ? parent.width - width - root.ui(4) : root.ui(4); anchors.verticalCenter: parent.verticalCenter; color: root.knob } MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.hdrEnabled = !root.hdrEnabled } }
            }
        }

        Item {
            width: parent.width; height: root.ui(64)
            RowLayout {
                anchors.fill: parent; spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "night"; color: root.ink }
                Text { Layout.fillWidth: true; text: "Night light"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(20) }
                Rectangle { Layout.preferredWidth: root.ui(64); Layout.preferredHeight: root.ui(36); radius: height / 2; color: root.nightLightEnabled ? root.accent : root.off; Rectangle { width: root.ui(28); height: width; radius: width / 2; x: root.nightLightEnabled ? parent.width - width - root.ui(4) : root.ui(4); anchors.verticalCenter: parent.verticalCenter; color: root.knob } MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.nightLightEnabled = !root.nightLightEnabled } }
            }
        }

        Item {
            width: parent.width; height: root.ui(76)
            RowLayout {
                anchors.fill: parent; spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "temperature"; color: root.ink }
                Text {
                    Layout.preferredWidth: root.ui(150)
                    Layout.minimumWidth: root.ui(150)
                    text: "Color\ntemperature"
                    color: root.ink
                    font.family: root.proseFont
                    font.pixelSize: root.ui(20)
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                }
                Slider {
                    id: temperatureSlider
                    Layout.fillWidth: true
                    Layout.minimumWidth: root.ui(105)
                    Layout.preferredWidth: root.ui(145)
                    Layout.preferredHeight: root.ui(34)
                    from: 2500
                    to: 6500
                    stepSize: 100
                    value: root.colorTemperature
                    onMoved: root.colorTemperature = Math.round(value / 100) * 100

                    background: Rectangle {
                        x: temperatureSlider.leftPadding
                        y: temperatureSlider.topPadding + temperatureSlider.availableHeight / 2 - height / 2
                        width: temperatureSlider.availableWidth
                        height: root.ui(6)
                        radius: height / 2
                        color: root.track
                        Rectangle {
                            width: temperatureSlider.visualPosition * parent.width
                            height: parent.height
                            radius: height / 2
                            color: root.accent
                        }
                    }

                    handle: Rectangle {
                        x: temperatureSlider.leftPadding + temperatureSlider.visualPosition * (temperatureSlider.availableWidth - width)
                        y: temperatureSlider.topPadding + temperatureSlider.availableHeight / 2 - height / 2
                        width: root.ui(28)
                        height: width
                        radius: width / 2
                        color: root.knob
                        border.color: root.controlBorder
                        border.width: root.ui(1)
                    }
                }
                Text { Layout.preferredWidth: root.ui(58); text: root.colorTemperature + "K"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(18); horizontalAlignment: Text.AlignRight }
            }
        }

        Item { width: parent.width; height: root.ui(20) }
        Rectangle { width: parent.width; height: root.ui(1); color: root.divider }
        Item { width: parent.width; height: root.ui(20) }

        Text { width: parent.width; height: root.ui(32); text: "POWER"; color: root.secondary; font.family: root.proseFont; font.pixelSize: root.ui(14); font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter }

        Item {
            width: parent.width; height: root.ui(64)
            RowLayout {
                anchors.fill: parent; spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "power"; color: root.ink }
                Text { Layout.fillWidth: true; text: "Turn display off after"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(20) }
                Rectangle {
                    Layout.preferredWidth: root.ui(282); Layout.minimumWidth: root.ui(190); Layout.preferredHeight: root.ui(52); radius: root.ui(12); color: root.control; border.color: root.controlBorder; border.width: root.ui(1)
                    Text { anchors.left: parent.left; anchors.leftMargin: root.ui(18); anchors.verticalCenter: parent.verticalCenter; text: root.powerValue; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(18) }
                    Text { anchors.right: parent.right; anchors.rightMargin: root.ui(15); anchors.verticalCenter: parent.verticalCenter; text: "⌄"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(25) }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.cyclePower() }
                }
            }
        }

        Item { width: parent.width; height: root.ui(20) }
        Rectangle { width: parent.width; height: root.ui(1); color: root.divider }
        Item { width: parent.width; height: root.ui(20) }

        Text { width: parent.width; height: root.ui(32); text: "EXTRA"; color: root.secondary; font.family: root.proseFont; font.pixelSize: root.ui(14); font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter }

        Item {
            width: parent.width; height: root.ui(64)
            RowLayout {
                anchors.fill: parent; spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "info"; color: root.ink }
                Text { Layout.fillWidth: true; text: "EDID information"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(20) }
                Text { Layout.preferredWidth: root.ui(26); text: "›"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(34); horizontalAlignment: Text.AlignRight }
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.extraView = root.extraView === "edid" ? "" : "edid" }
        }

        Item {
            width: parent.width; height: root.ui(64)
            RowLayout {
                anchors.fill: parent; spacing: root.ui(16)
                DisplayIcon { Layout.preferredWidth: root.ui(42); Layout.preferredHeight: root.ui(42); kind: "compositor"; color: root.ink }
                Text { Layout.fillWidth: true; text: "Advanced compositor options"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(20) }
                Text { Layout.preferredWidth: root.ui(26); text: "›"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(34); horizontalAlignment: Text.AlignRight }
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.extraView = root.extraView === "compositor" ? "" : "compositor" }
        }

        Column {
            width: parent.width
            visible: root.extraView !== ""
            height: visible ? implicitHeight : 0
            spacing: root.ui(8)

            Rectangle {
                width: parent.width
                height: root.ui(44)
                radius: root.ui(10)
                color: root.control
                border.color: root.controlBorder
                border.width: root.ui(1)
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: root.ui(14)
                    text: "‹  Back to Extra"
                    color: root.accent
                    font.family: root.proseFont
                    font.pixelSize: root.ui(16)
                    verticalAlignment: Text.AlignVCenter
                }
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.extraView = "" }
            }

            Rectangle {
                width: parent.width
                height: root.extraView === "edid" ? root.ui(108) : root.ui(168)
                radius: root.ui(10)
                color: root.control
                border.color: root.controlBorder
                border.width: root.ui(1)

                Column {
                    anchors.fill: parent
                    anchors.margins: root.ui(14)
                    spacing: root.ui(5)

                    Text {
                        width: parent.width
                        text: root.extraView === "edid" ? "EDID information" : "Advanced compositor options"
                        color: root.ink
                        font.family: root.proseFont
                        font.pixelSize: root.ui(17)
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: root.extraView === "edid"
                            ? "Output: " + (root.display && root.display.name ? root.display.name : "Unknown") +
                              "\nMode: " + root.resolutionText() + "\nEDID data is not exposed by the current monitor backend."
                            : "Read-only compositor state for this output."
                        color: root.secondary
                        font.family: root.proseFont
                        font.pixelSize: root.ui(14)
                    }

                    RowLayout {
                        visible: root.extraView === "compositor"
                        width: parent.width
                        height: root.ui(34)
                        Text { Layout.fillWidth: true; text: "Allow tearing"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(15) }
                        CheckBox { checked: root.allowTearing; onToggled: root.allowTearing = checked }
                    }
                    RowLayout {
                        visible: root.extraView === "compositor"
                        width: parent.width
                        height: root.ui(34)
                        Text { Layout.fillWidth: true; text: "Direct scanout"; color: root.ink; font.family: root.proseFont; font.pixelSize: root.ui(15) }
                        CheckBox { checked: root.directScanout; onToggled: root.directScanout = checked }
                    }
                }
            }
        }

        Item { width: parent.width; height: root.ui(10) }
    }
}
