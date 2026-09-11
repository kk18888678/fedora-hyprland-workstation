import QtQuick
import QtQuick.Layouts
import "../../../ui"
import "../../../theme"
import "../NotificationLogic.js" as Logic

// One shared notification card for popup, Active, and History. Every surface
// keeps the same title -> two-line body -> actions hierarchy.
Item {
    id: root

    property string app: ""
    property string appIcon: ""
    property string desktopEntry: ""
    property string summary: ""
    property string body: ""
    property string image: ""
    property string glyph: ""
    property string execArgv: ""
    property var actions: []
    property string defaultActionText: ""
    property int urgency: 1
    property bool interactive: true
    property bool showDismiss: true
    property bool showArchive: false
    property bool showActions: true
    property bool defaultActionEnabled: true
    property bool actionButtonsEnabled: true
    property string timestampLabel: ""

    readonly property bool hovered: toastHover.hovered
    readonly property int actionCount: (root.defaultActionText !== "" ? 1 : 0)
        + (root.actions && typeof root.actions.length === "number" ? root.actions.length : 0)
        + (root.showArchive ? 1 : 0)
    readonly property int actionGroupWidth: root.actionCount > 0
        ? root.actionCount * 92 + (root.actionCount - 1) * Theme.spacingXs
        : 0
    readonly property string styledBody: Logic.styledBody(root.body, root.app, root.appIcon)

    signal dismissed()
    signal activated()
    signal defaultActionInvoked()
    signal actionInvoked(string identifier)
    signal archiveRequested()

    implicitWidth: 380
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

    function imageSource() {
        var rawImage = String(root.image || "")
        if (rawImage.indexOf("image://") === 0) return rawImage
        var notificationImage = root.localImageSource(root.image)
        return notificationImage !== "" ? notificationImage : root.localImageSource(root.appIcon)
    }

    HoverHandler { id: toastHover }

    Rectangle {
        id: toastCard
        width: root.width > 0 ? root.width : root.implicitWidth
        implicitHeight: cardContent.implicitHeight + Theme.spacingSm * 2
        height: implicitHeight
        radius: Theme.radiusMd
        color: Theme.notifications.background
        border.color: root.urgency === 2 ? Theme.error : (root.hovered ? Theme.notifications.border : Theme.border)
        border.width: root.urgency === 2 ? Theme.borderWidthFocus : Theme.borderWidthDefault

        Rectangle {
            width: 3
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            radius: width / 2
            color: root.urgency === 2 ? Theme.error : Theme.notifications.countdown
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.interactive
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
                mouse.accepted = true
                if (mouse.button === Qt.RightButton) root.dismissed()
                else root.activated()
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

                Item {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSm
                        color: Theme.surface
                    }

                    Image {
                        id: iconImage
                        anchors.fill: parent
                        anchors.margins: 4
                        source: root.imageSource()
                        sourceSize: Qt.size(40, 40)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }

                    AureliaIcon {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        visible: iconImage.status !== Image.Ready && root.glyph === ""
                        name: root.iconName(root.appIcon)
                        iconSize: 24
                        tint: Theme.accent
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: iconImage.status !== Image.Ready && root.glyph !== ""
                        text: root.glyph
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXl
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
                            textFormat: Text.PlainText
                            text: root.summary === ""
                                ? (root.app === "" ? "Notification" : root.app)
                                : root.summary
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Theme.fontWeightMedium
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                    }

                    Text {
                        Layout.fillWidth: true
                        visible: root.styledBody.length > 0
                        text: root.styledBody
                        textFormat: Text.StyledText
                        color: Theme.textSecondary
                        font.family: Theme.fontFamilyProse
                        font.pixelSize: Theme.fontSizeSm
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Item {
                        id: actionContainer
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? actionFlow.implicitHeight : 0
                        visible: root.showActions && (root.defaultActionText !== "" || (root.actions && root.actions.length > 0) || root.showArchive)

                        Flow {
                            id: actionFlow
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, root.actionGroupWidth)
                            spacing: Theme.spacingXs

                            AureliaActionButton {
                                visible: root.defaultActionText !== ""
                                enabled: root.defaultActionEnabled
                                compact: true
                                centerLabel: true
                                label: root.defaultActionText
                                onTriggered: root.defaultActionInvoked()
                            }

                            Repeater {
                                model: root.actions
                                delegate: AureliaActionButton {
                                    required property var modelData
                                    enabled: root.actionButtonsEnabled
                                    compact: true
                                    centerLabel: true
                                    label: modelData.text || "Action"
                                    onTriggered: root.actionInvoked(String(modelData.identifier || ""))
                                }
                            }

                            AureliaActionButton {
                                visible: root.showArchive
                                enabled: root.actionButtonsEnabled
                                compact: true
                                centerLabel: true
                                label: "Archive"
                                onTriggered: root.archiveRequested()
                            }
                        }
                    }

                }
            }
        }

        Item {
            id: closeButton
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Theme.spacingXs
            anchors.rightMargin: Theme.spacingXs
            width: 18
            height: 18
            z: 2
            visible: root.showDismiss && root.hovered

            Text {
                anchors.centerIn: parent
                text: "×"
                color: closeMouse.containsMouse ? Theme.text : Theme.textSubtle
                font.pixelSize: Theme.fontSizeLg
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    mouse.accepted = true
                    root.dismissed()
                }
            }
        }
    }
}
