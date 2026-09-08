import QtQuick
import Quickshell
import "../theme"

// A small, standalone tooltip surface for bar widgets. QtQuick.Controls.ToolTip
// is parented through the control overlay and can be clipped by a short
// layer-shell bar. This primitive is an anchored PopupWindow, so its geometry
// is resolved against the real bar window and remains fully visible below a
// top bar (or above a bottom bar).
PopupWindow {
    id: root

    property var triggerItem: null
    property var bar: null
    property string text: ""
    property bool hovered: false
    property int delay: 400
    property int margin: Theme.spacingSm
    property int maxTextWidth: 260
    property int horizontalPadding: Theme.spacingSm
    property int verticalPadding: Theme.spacingXs
    property bool revealed: false

    readonly property var anchorWindow: triggerItem && triggerItem.QsWindow && triggerItem.QsWindow.window
        ? triggerItem.QsWindow.window
        : null

    readonly property int contentWidth: Math.max(80, Math.min(maxTextWidth, tooltipMetrics.advanceWidth))

    visible: root.hovered && root.revealed && root.anchorWindow !== null && root.triggerItem !== null && root.text !== ""
    color: "transparent"
    implicitWidth: contentWidth + horizontalPadding * 2
    implicitHeight: tooltipText.implicitHeight + verticalPadding * 2

    function dismiss() {
        revealed = false
        showTimer.stop()
    }

    function reveal() {
        if (!root.hovered || root.text === "" || root.anchorWindow === null) return
        root.revealed = true
    }

    onHoveredChanged: {
        if (hovered) showTimer.restart()
        else dismiss()
    }

    onTextChanged: {
        if (root.hovered) showTimer.restart()
    }

    Component.onCompleted: {
        if (root.hovered) showTimer.restart()
    }

    Timer {
        id: showTimer
        interval: root.delay
        repeat: false
        onTriggered: root.reveal()
    }

    TextMetrics {
        id: tooltipMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeXs
        text: root.text
    }

    anchor {
        id: tooltipAnchor
        window: root.anchorWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
            if (!root.triggerItem || !root.anchorWindow) return

            var target = root.triggerItem
            var localX = target.width / 2 - root.implicitWidth / 2
            var localY = target.height + root.margin
            var position = root.bar ? String(root.bar.position || "top") : "top"

            if (position === "bottom") {
                localY = -root.implicitHeight - root.margin
            } else if (position === "left") {
                localX = target.width + root.margin
                localY = target.height / 2 - root.implicitHeight / 2
            } else if (position === "right") {
                localX = -root.implicitWidth - root.margin
                localY = target.height / 2 - root.implicitHeight / 2
            }

            var point = root.anchorWindow.contentItem.mapFromItem(target, localX, localY)
            if (position === "top" || position === "bottom") {
                point.x = Math.max(root.margin, Math.min(point.x, root.anchorWindow.width - root.implicitWidth - root.margin))
            } else {
                point.y = Math.max(root.margin, Math.min(point.y, root.anchorWindow.height - root.implicitHeight - root.margin))
            }
            tooltipAnchor.rect.x = Math.round(point.x)
            tooltipAnchor.rect.y = Math.round(point.y)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Theme.surfaceElevated
        border.color: Theme.borderActive
        border.width: Theme.borderWidthDefault

        Text {
            id: tooltipText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: root.contentWidth
            height: implicitHeight
            text: root.text
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
