import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../ui"
import "../../../theme"
import "../NotificationLogic.js" as Logic

// Shared presentational card for popup, Active, and History. Its visual layout
// follows the Omarchy NotificationCard: a compact leading image/glyph slot,
// Liberation Sans title/body text, and a restrained close affordance.
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
    property bool showActions: defaultActionText !== ""
    property bool defaultActionEnabled: true
    property bool actionButtonsEnabled: true
    property string timestampLabel: ""

    readonly property bool hovered: toastHover.hovered
    readonly property int actionCount: (root.defaultActionText !== "" ? 1 : 0)
        + (root.actions && typeof root.actions.length === "number" ? root.actions.length : 0)
        + (root.showArchive ? 1 : 0)
    readonly property int actionGroupWidth: root.actionCount > 0
        ? root.actionCount * Theme.scaleGeometry(64)
            + (root.actionCount - 1) * Theme.spacingXs
        : 0
    readonly property bool hasGlyph: root.glyph.length > 0
    readonly property string smallIconSource: root.image.length > 0
        ? root.image
        : root.iconSource(root.appIcon)
    readonly property bool hasSmallIcon: root.smallIconSource.length > 0
    readonly property bool compactGlyph: Logic.shouldRenderCompactGlyph(
        root.glyph, root.smallIconSource, root.singleLineToast)
    readonly property bool summaryStartsWithGlyph: Logic.summaryStartsWithGlyph(root.summary)
    readonly property bool singleLineToast: root.sanitizedBody.length === 0
    readonly property bool collapseRedundantIcon: root.singleLineToast &&
        !root.hasGlyph && root.summaryStartsWithGlyph
    readonly property string sanitizedBody: Logic.sanitizeBody(root.body, root.app, root.appIcon)
    readonly property string styledBody: Logic.styledBody(root.body, root.app, root.appIcon)
    readonly property color bodyColor: Qt.darker(Theme.notifications.text, 1.15)
    readonly property color dimColor: Qt.darker(Theme.notifications.text, 1.4)

    signal dismissed()
    signal activated()
    signal defaultActionInvoked()
    signal actionInvoked(string identifier)
    signal archiveRequested()

    implicitWidth: 416
    implicitHeight: toastCard.implicitHeight

    function iconSource(value) {
        var source = String(value || "")
        if (source === "") return ""
        if (source.indexOf("file://") === 0 || source.indexOf("image://") === 0) return source
        if (source.charAt(0) === "/") return source
        return Quickshell.iconPath(source, "application-x-executable")
    }

    function iconName(value) {
        var source = String(value || "")
        if (source === "" || source.indexOf("file://") === 0 ||
            source.indexOf("image://") === 0 || source.charAt(0) === "/") {
            return "application-x-executable"
        }
        return source
    }

    HoverHandler { id: toastHover }

    Rectangle {
        id: toastCard
        width: Math.min(root.width > 0 ? root.width : root.implicitWidth, root.implicitWidth)
        implicitHeight: mainColumn.implicitHeight + Theme.borderWidthFocus * 2
        height: implicitHeight
        radius: 0
        color: Theme.notifications.background
        border.color: root.urgency === 2 ? Theme.error : Theme.notifications.border
        border.width: Theme.borderWidthFocus
        clip: true

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
            id: mainColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Theme.borderWidthFocus
            anchors.leftMargin: Theme.borderWidthFocus
            anchors.rightMargin: Theme.borderWidthFocus
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingMd
                Layout.rightMargin: Theme.spacingMd
                Layout.topMargin: root.singleLineToast ? Theme.scaleGeometry(7) : Theme.scaleGeometry(10)
                Layout.bottomMargin: root.singleLineToast ? Theme.scaleGeometry(7) : Theme.scaleGeometry(10)
                spacing: root.collapseRedundantIcon ? 0
                    : (root.compactGlyph ? Theme.scaleGeometry(8) : Theme.spacingMd)

                Item {
                    id: smallIconSlot
                    Layout.preferredWidth: visible ? Theme.scaleGeometry(40) : 0
                    Layout.preferredHeight: visible ? Theme.scaleGeometry(40) : 0
                    Layout.alignment: Qt.AlignVCenter
                    visible: !root.collapseRedundantIcon && !root.compactGlyph &&
                        (root.hasSmallIcon || root.hasGlyph) &&
                        (root.hasGlyph || smallIconImage.status !== Image.Error)

                    Image {
                        id: smallIconImage
                        anchors.fill: parent
                        source: root.smallIconSource
                        // Decode above display resolution before the thumbnail
                        // is minified. This keeps screenshot previews crisp
                        // without changing Omarchy's 40px visual slot.
                        sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio * 4
                        sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio * 4
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        visible: !root.hasGlyph || smallIconImage.status === Image.Ready
                    }

                    // Preserve native app artwork. This fallback is used only
                    // when the image cannot be resolved; semantic names such
                    // as camera-photo still use Aurelia's native glyph map.
                    AureliaIcon {
                        anchors.centerIn: parent
                        width: Theme.scaleGeometry(24)
                        height: Theme.scaleGeometry(24)
                        visible: !root.hasGlyph && smallIconImage.status !== Image.Ready && root.appIcon !== ""
                        name: root.iconName(root.appIcon)
                        iconSize: Theme.scaleGeometry(24)
                        preserveColors: true
                        tint: root.urgency === 2 ? Theme.error : Theme.notifications.text
                    }

                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        visible: root.hasGlyph && smallIconImage.status !== Image.Ready
                        text: root.glyph
                        color: Theme.notifications.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.scaleGeometry(28)
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.compactGlyph
                    text: root.glyph
                    color: Theme.notifications.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.scaleGeometry(14)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: Theme.scaleGeometry(10)
                    spacing: Theme.scaleGeometry(2)

                    Text {
                        Layout.fillWidth: true
                        visible: root.summary.length > 0
                        textFormat: Text.PlainText
                        text: root.summary
                        color: Theme.notifications.text
                        font.family: "Liberation Sans"
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Theme.fontWeightBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.scaleGeometry(2)
                        visible: root.sanitizedBody.length > 0
                        text: root.styledBody
                        textFormat: Text.StyledText
                        color: root.bodyColor
                        font.family: "Liberation Sans"
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Theme.fontWeightNormal
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }

            // Keep the reference card compact. Only a notification with an
            // explicit default action gets the small Open-style footer; the
            // whole card remains the primary interaction surface.
            Item {
                id: actionContainer
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? actionToolbar.implicitHeight : 0
                Layout.topMargin: Theme.scaleGeometry(2)
                visible: root.showActions && (root.defaultActionText !== "" ||
                    (root.actions && root.actions.length > 0) || root.showArchive)

                ColumnLayout {
                    id: actionToolbar
                    width: parent.width
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: actionFlow.implicitHeight

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
                                primary: false
                                border.width: 0
                                border.color: "transparent"
                                width: Theme.scaleGeometry(64)
                                height: Theme.scaleGeometry(28)
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
                                    border.width: 0
                                    border.color: "transparent"
                                    width: Theme.scaleGeometry(64)
                                    height: Theme.scaleGeometry(28)
                                    label: modelData.text || "Action"
                                    onTriggered: root.actionInvoked(String(modelData.identifier || ""))
                                }
                            }

                            AureliaActionButton {
                                visible: root.showArchive
                                enabled: root.actionButtonsEnabled
                                compact: true
                                centerLabel: true
                                border.width: 0
                                border.color: "transparent"
                                width: Theme.scaleGeometry(64)
                                height: Theme.scaleGeometry(28)
                                label: "Archive"
                                onTriggered: root.archiveRequested()
                            }
                        }
                    }
                }
            }
        }

        // Hover-revealed close, matching the reference card's quiet idle state.
        Item {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Theme.borderWidthFocus + Theme.scaleGeometry(3)
            anchors.rightMargin: Theme.borderWidthFocus + Theme.scaleGeometry(3)
            width: Theme.scaleGeometry(18)
            height: Theme.scaleGeometry(18)
            z: 2
            visible: opacity > 0
            opacity: root.showDismiss && root.hovered ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.effectiveDurationFast }
            }

            Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "✕"
                color: closeMouse.containsMouse ? Theme.notifications.text : root.dimColor
                font.family: "Liberation Sans"
                font.pixelSize: Theme.scaleGeometry(14)
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
