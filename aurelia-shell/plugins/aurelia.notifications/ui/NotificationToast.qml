import QtQuick
import QtQuick.Layouts
import "../../../ui"
import "../../../theme"

// One content-driven notification card shared by popup, Active, and History.
// The root height is derived from the complete column, including actions and
// media, so the lower part can never be clipped by a fixed delegate height.
Item {
    id: root

    property string app: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property string image: ""
    property var actions: []
    property string defaultActionText: ""
    property int urgency: 1
    property bool interactive: true
    property bool showDismiss: true
    property bool showActions: true
    property string timestampLabel: ""

    readonly property bool hovered: toastHover.hovered

    signal dismissed()
    signal activated()
    signal defaultActionInvoked()
    signal actionInvoked(string identifier)

    implicitWidth: 340
    implicitHeight: toastCard.implicitHeight

    function iconName(value) {
        var source = String(value || "")
        if (source === "" || source.indexOf("file://") === 0 || source.charAt(0) === "/") return "application-x-executable"
        return source
    }

    function localImageSource(value) {
        var source = String(value || "")
        if (source.indexOf("file://") === 0) {
            try { source = decodeURIComponent(source.slice(7)) } catch (error) { return "" }
        }
        return source.charAt(0) === "/" ? source : ""
    }

    HoverHandler { id: toastHover }

    Rectangle {
        id: toastCard
        width: root.width > 0 ? root.width : root.implicitWidth
        implicitHeight: cardContent.implicitHeight + Theme.spacingSm * 2
        height: implicitHeight
        radius: Theme.radiusMd
        color: Theme.surfaceElevated
        border.color: root.urgency === 2 ? Theme.error : (root.hovered ? Theme.borderActive : Theme.border)
        border.width: root.urgency === 2 ? Theme.borderWidthFocus : Theme.borderWidthDefault

        Rectangle {
            width: 3
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            radius: width / 2
            color: root.urgency === 2 ? Theme.error : Theme.accent
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.activated()
            }
        }

        ColumnLayout {
            id: cardContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Theme.spacingMd
            anchors.rightMargin: Theme.spacingSm
            anchors.topMargin: Theme.spacingSm
            spacing: Theme.spacingXs

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: Theme.radiusSm
                    color: Theme.surface

                    AureliaIcon {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        name: root.iconName(root.appIcon)
                        iconSize: 18
                        tint: Theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs

                        Text {
                            Layout.fillWidth: true
                            text: {
                                var label = root.app === "" ? "Notification" : root.app
                                return root.timestampLabel === "" ? label : label + " · " + root.timestampLabel
                            }
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: root.showDismiss
                            text: "×"
                            color: closeMouse.containsMouse ? Theme.text : Theme.textSubtle
                            font.pixelSize: Theme.fontSizeLg

                            MouseArea {
                                id: closeMouse
                                anchors.fill: parent
                                anchors.margins: -Theme.spacingXs
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    mouse.accepted = true
                                    root.dismissed()
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.summary
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Theme.fontWeightMedium
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.body
                        color: Theme.textSecondary
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeSm
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    Image {
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 80 : 0
                        visible: root.localImageSource(root.image) !== "" && status !== Image.Error
                        source: root.localImageSource(root.image)
                        sourceSize: Qt.size(300, 80)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: false
                        smooth: true
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs
                        visible: root.showActions && (root.defaultActionText !== "" || (root.actions && root.actions.length > 0))

                        AureliaActionButton {
                            visible: root.defaultActionText !== ""
                            compact: true
                            label: root.defaultActionText
                            onTriggered: root.defaultActionInvoked()
                        }

                        Repeater {
                            model: root.actions
                            delegate: AureliaActionButton {
                                required property var modelData
                                compact: true
                                label: modelData.text || "Action"
                                onTriggered: root.actionInvoked(String(modelData.identifier || ""))
                            }
                        }
                    }
                }
            }
        }
    }
}
