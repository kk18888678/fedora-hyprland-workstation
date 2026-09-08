import QtQuick
import QtQuick.Layouts
import "../../../ui"
import "../../../theme"

// Compact center row shared by Active and History views.
Item {
    id: root

    property string app: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property int urgency: 1
    property double timestamp: 0
    property bool dismissible: false

    signal dismissRequested()

    implicitHeight: 66

    function iconName(value) {
        var source = String(value || "")
        if (source === "" || source.indexOf("file://") === 0 || source.charAt(0) === "/") return "application-x-executable"
        return source
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: rowHover.hovered ? Theme.selection : Theme.surface
        border.color: root.urgency === 2 ? Theme.error : Theme.border
        border.width: Theme.borderWidthDefault

        HoverHandler { id: rowHover }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingSm
            spacing: Theme.spacingSm

            AureliaIcon {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                name: root.iconName(root.appIcon)
                iconSize: 20
                tint: root.urgency === 2 ? Theme.error : Theme.accent
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: root.summary
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Theme.fontWeightMedium
                        elide: Text.ElideRight
                    }
                    Text {
                        text: root.timestamp > 0 ? Qt.formatTime(new Date(root.timestamp), "HH:mm") : ""
                        color: Theme.textSubtle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.app + (root.app !== "" && root.body !== "" ? " · " : "") + root.body
                    color: Theme.textSecondary
                    font.family: Theme.fontFamilyProse
                    font.pixelSize: Theme.fontSizeXs
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                }
            }

            Text {
                visible: root.dismissible
                text: "×"
                color: rowClose.containsMouse ? Theme.text : Theme.textSubtle
                font.pixelSize: Theme.fontSizeLg

                MouseArea {
                    id: rowClose
                    anchors.fill: parent
                    anchors.margins: -Theme.spacingXs
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        root.dismissRequested()
                    }
                }
            }
        }
    }
}
