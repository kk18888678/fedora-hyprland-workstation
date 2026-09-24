import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../ui"
import "../../../theme"
import "../NotificationLogic.js" as Logic

// Shared presentational card for the transient popup and the Inbox. Its visual
// layout follows the Omarchy NotificationCard: a compact leading image/glyph
// slot, Liberation Sans title/body text, and a restrained close affordance.
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
    // Every card exposes a Copy affordance unless a surface explicitly opts out.
    property bool showCopy: true
    // A notification may offer only non-default actions. The action row must
    // stay visible for those too, not just for an explicit default action.
    property bool showActions: defaultActionText !== "" || actionItemsCount > 0
    property bool defaultActionEnabled: true
    property bool actionButtonsEnabled: true
    property string timestampLabel: ""
    // Capture the model identity at construction time so a close click cannot
    // lose it while a ListView/Repeater is updating its delegate index.
    property var identityOriginalId
    property real identityTimestamp: 0
    property int identityIndex: -1

    readonly property bool hovered: toastHover.hovered
    // The card itself is a tab stop so keyboard users can reveal the quiet
    // Copy affordance. Copy stays hidden until the card is hovered or focused,
    // which also keeps it out of hit-testing while invisible.
    readonly property bool copyRevealed: root.hovered || root.focus || copyButton.focus
    activeFocusOnTab: true
    // Actions arrive either as a plain JS array (fixtures/tests) or as the
    // nested list model Qt materializes for a ListModel array role (the
    // production Service path). The latter exposes `.count` and no `.length`,
    // so count both forms or the toolbar under-measures and wraps.
    readonly property int actionItemsCount: {
        var value = root.actions
        if (!value) return 0
        if (typeof value.length === "number") return value.length
        if (typeof value.count === "number") return value.count
        return 0
    }
    readonly property int actionCount: (root.defaultActionText !== "" ? 1 : 0)
        + root.actionItemsCount
    readonly property int actionGroupWidth: root.actionCount > 0
        ? root.actionCount * Theme.scaleGeometry(64)
            + (root.actionCount - 1) * Theme.spacingXs
        : 0
    // The action row is anchored to the stable card width rather than to its
    // layout-managed parent. A ColumnLayout can leave a child that became
    // visible after creation at width 0, so `parent.width` is not a reliable
    // basis for the Flow's layout.
    readonly property real actionContentWidth: Math.max(0,
        (toastCard.width > 0 ? toastCard.width : root.implicitWidth)
            - Theme.borderWidthFocus * 2)
    readonly property real actionAvailableWidth: Math.max(0,
        root.actionContentWidth - Theme.spacingMd * 2)
    readonly property bool hasGlyph: root.glyph.length > 0
    readonly property string smallIconSource: root.image.length > 0
        ? root.image
        : root.iconSource(root.appIcon)
    readonly property bool hasSmallIcon: root.smallIconSource.length > 0
    readonly property bool appIconIsLocal: root.appIcon.indexOf("file://") === 0 ||
        root.appIcon.indexOf("image://") === 0 || root.appIcon.charAt(0) === "/"
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

    signal dismissed(var originalId, real timestamp, int index)
    signal activated()
    signal defaultActionInvoked()
    signal actionInvoked(string identifier)
    signal copyRequested()

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

    function emitDismissed() {
        var originalId = root.identityOriginalId
        var timestamp = Number(root.identityTimestamp)
        var index = Number(root.identityIndex)
        if (!isFinite(timestamp)) timestamp = 0
        if (!isFinite(index)) index = -1
        root.dismissed(originalId, timestamp, index)
    }

    function dismissFromClose() {
        root.emitDismissed()
    }

    function dismissFromPointer(button) {
        if (button === Qt.RightButton) {
            root.emitDismissed()
            return "dismiss"
        }
        root.activated()
        return "activate"
    }

    HoverHandler { id: toastHover }

    Rectangle {
        id: toastCard
        objectName: "notificationToastCard"
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
                root.dismissFromPointer(mouse.button)
            }
        }

        ColumnLayout {
            id: mainColumn
            objectName: "notificationMainColumn"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Theme.borderWidthFocus
            anchors.leftMargin: Theme.borderWidthFocus
            anchors.rightMargin: Theme.borderWidthFocus
            spacing: 0

            RowLayout {
                id: mainRow
                objectName: "notificationMainRow"
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingMd
                Layout.rightMargin: Theme.spacingMd
                Layout.topMargin: root.singleLineToast ? Theme.scaleGeometry(7) : Theme.scaleGeometry(10)
                Layout.bottomMargin: root.singleLineToast ? Theme.scaleGeometry(7) : Theme.scaleGeometry(10)
                spacing: root.collapseRedundantIcon ? 0
                    : (root.compactGlyph ? Theme.scaleGeometry(8) : Theme.spacingMd)

                Item {
                    id: smallIconSlot
                    objectName: "notificationIconSlot"
                    Layout.preferredWidth: visible ? Theme.scaleGeometry(40) : 0
                    Layout.preferredHeight: visible ? Theme.scaleGeometry(40) : 0
                    Layout.alignment: Qt.AlignVCenter
                    visible: !root.collapseRedundantIcon && !root.compactGlyph &&
                        (root.hasSmallIcon || root.hasGlyph) &&
                        (root.hasGlyph || smallIconImage.status !== Image.Error)

                    Image {
                        id: smallIconImage
                        objectName: "notificationSourceIcon"
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
                        objectName: "notificationSourceIconFallback"
                        anchors.centerIn: parent
                        width: Theme.scaleGeometry(24)
                        height: Theme.scaleGeometry(24)
                        visible: !root.hasGlyph && smallIconImage.status !== Image.Ready && root.appIcon !== ""
                        // Resolve a real local/file app icon directly instead of
                        // collapsing it to the generic executable fallback.
                        name: root.appIconIsLocal ? "" : root.iconName(root.appIcon)
                        sourcePath: root.appIconIsLocal ? root.appIcon : ""
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
                    id: contentColumn
                    objectName: "notificationContentColumn"
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: Theme.scaleGeometry(10)
                    spacing: Theme.scaleGeometry(2)

                    // Source attribution: application name on the left, the
                    // computed timestamp label next to it, and the icon-only
                    // Copy affordance pinned to the right edge of the title
                    // row. The app name is the only flexible cell, so it
                    // elides first and the Copy icon stays reachable even
                    // when the app name is very long.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Theme.scaleGeometry(1)
                        spacing: Theme.scaleGeometry(6)
                        visible: root.app.length > 0 || root.timestampLabel.length > 0 || root.showCopy

                        Text {
                            objectName: "notificationSourceApp"
                            Layout.fillWidth: true
                            visible: root.app.length > 0
                            textFormat: Text.PlainText
                            text: root.app
                            color: root.dimColor
                            font.family: "Liberation Sans"
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightMedium
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            objectName: "notificationTimestamp"
                            Layout.alignment: Qt.AlignRight
                            visible: root.timestampLabel.length > 0
                            textFormat: Text.PlainText
                            text: root.timestampLabel
                            color: root.dimColor
                            font.family: "Liberation Sans"
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightNormal
                        }

                        // Icon-only Copy. It deliberately carries no text
                        // label and is not a link; the tooltip keeps it
                        // discoverable and keyboard activation matches the
                        // pointer path.
                        AureliaIconButton {
                            id: copyButton
                            objectName: "notificationCopyAction"
                            Layout.alignment: Qt.AlignVCenter
                            visible: root.showCopy && root.copyRevealed
                            enabled: root.actionButtonsEnabled
                            icon: "edit-copy"
                            tooltip: "Copy notification"
                            onTriggered: root.copyRequested()
                        }
                    }

                    Text {
                        objectName: "notificationSummary"
                        Layout.fillWidth: true
                        visible: root.summary.length > 0
                        textFormat: Text.PlainText
                        text: root.summary
                        color: Theme.notifications.text
                        font.family: "Liberation Sans"
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Theme.fontWeightBold
                        horizontalAlignment: Text.AlignLeft
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        objectName: "notificationBody"
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.scaleGeometry(2)
                        visible: root.sanitizedBody.length > 0
                        text: root.styledBody
                        textFormat: Text.StyledText
                        color: root.bodyColor
                        font.family: "Liberation Sans"
                        font.pixelSize: Theme.fontSizeSm
                        font.weight: Theme.fontWeightNormal
                        horizontalAlignment: Text.AlignLeft
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
                objectName: "notificationActionContainer"
                Layout.fillWidth: true
                // Bind the container height to the Flow's own implicit height.
                // Routing it through actionToolbar.implicitHeight observed a
                // stale zero while the nested Flow reflowed, which clipped a
                // wrapped action row.
                Layout.preferredHeight: visible ? actionFlow.implicitHeight : 0
                Layout.topMargin: Theme.scaleGeometry(2)
                // Leave breathing room between the action row and the card's
                // bottom border so the button never touches the edge.
                Layout.bottomMargin: visible ? Theme.scaleGeometry(6) : 0
                visible: root.showActions && (root.defaultActionText !== "" ||
                    root.actionItemsCount > 0)

                ColumnLayout {
                    id: actionToolbar
                    width: parent.width
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: actionFlow.implicitHeight

                        Flow {
                            id: actionFlow
                            objectName: "notificationActionFlow"
                            // Derive width and centering from the stable card
                            // width. QQuickFlow does not re-run its layout when
                            // its own width later changes, so force a reflow on
                            // every width change; the explicit width still wraps
                            // when the options no longer fit.
                            width: Math.min(root.actionAvailableWidth, root.actionGroupWidth)
                            x: Math.max(0, (root.actionContentWidth - width) / 2)
                            spacing: Theme.spacingXs
                            onWidthChanged: forceLayout()

                            AureliaActionButton {
                                objectName: "notificationActionButton"
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
                                    objectName: "notificationActionButton"
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
                    root.dismissFromClose()
                }
            }
        }
    }
}
