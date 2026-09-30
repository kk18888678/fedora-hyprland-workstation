import QtQuick
import Quickshell
import "../theme"

// A small, standalone tooltip surface for bar widgets. QtQuick.Controls.ToolTip
// is parented through the control overlay and can be clipped by a short
// layer-shell bar. This primitive is an anchored PopupWindow, so its geometry
// is resolved against the real bar window and remains fully visible below a
// top bar (or above a bottom bar).
//
// The visible body lives in AureliaToolTipContent so the bar host and the
// in-panel AureliaInlineToolTip host cannot drift apart. The plain `text` API
// stays backward compatible for the existing bar-widget callers.
PopupWindow {
    id: root

    property var triggerItem: null
    property var bar: null
    property string text: ""
    property var lines: []
    property var list: []
    property var footer: null
    property bool hovered: false
    property int delay: 400
    property int margin: 6
    property int horizontalPadding: Theme.spacingSm + 2
    property int verticalPadding: Theme.spacingXs + 3
    property bool revealed: false

    readonly property var anchorWindow: triggerItem && triggerItem.QsWindow && triggerItem.QsWindow.window
        ? triggerItem.QsWindow.window
        : null
    readonly property bool hasContent: text !== "" ||
        (Array.isArray(lines) && lines.length > 0) ||
        (Array.isArray(list) && list.length > 0) ||
        (footer !== null && footer !== undefined && String(footer.text || "") !== "")

    visible: root.hovered && root.revealed && root.anchorWindow !== null &&
        root.triggerItem !== null && root.hasContent
    color: "transparent"
    implicitWidth: tooltipBody.implicitWidth + horizontalPadding * 2
    implicitHeight: tooltipBody.implicitHeight + verticalPadding * 2

    function dismiss() {
        revealed = false
        showTimer.stop()
    }

    function reveal() {
        if (!root.hovered || !root.hasContent || root.anchorWindow === null) return
        root.revealed = true
    }

    onHoveredChanged: {
        if (hovered) showTimer.restart()
        else dismiss()
    }

    onTextChanged: {
        if (root.hovered) showTimer.restart()
    }

    onLinesChanged: {
        if (root.hovered) showTimer.restart()
    }

    onListChanged: {
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
            // A null bar is the panel context: place below the trigger and
            // flip above when the surface would run past the window edge.
            var position = root.bar ? String(root.bar.position || "top") : ""

            if (position === "bottom") {
                localY = -root.implicitHeight - root.margin
            } else if (position === "left") {
                localX = target.width + root.margin
                localY = target.height / 2 - root.implicitHeight / 2
            } else if (position === "right") {
                localX = -root.implicitWidth - root.margin
                localY = target.height / 2 - root.implicitHeight / 2
            }

            if (typeof root.anchorWindow.mapFromItem !== "function") {
                console.error("[TOOLTIP] anchor_mapping_failed reason=invalid_trigger_item")
                return
            }

            var point = root.anchorWindow.mapFromItem(target, localX, localY)
            if (position === "left" || position === "right") {
                point.y = Math.max(root.margin, Math.min(point.y, root.anchorWindow.height - root.implicitHeight - root.margin))
            } else {
                // Generic auto flip: a below-placement that would overflow the
                // window is moved above the trigger instead.
                if (position !== "bottom" &&
                    point.y + root.implicitHeight > root.anchorWindow.height - root.margin) {
                    point.y = root.anchorWindow.mapFromItem(
                        target, localX, -root.implicitHeight - root.margin).y
                }
                point.x = Math.max(root.margin, Math.min(point.x, root.anchorWindow.width - root.implicitWidth - root.margin))
            }
            tooltipAnchor.rect.x = Math.round(point.x)
            tooltipAnchor.rect.y = Math.round(point.y)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Theme.tooltip.background
        border.color: Theme.tooltip.border
        border.width: Theme.borderWidthDefault

        AureliaToolTipContent {
            id: tooltipBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 0
            anchors.leftMargin: root.horizontalPadding
            anchors.rightMargin: root.horizontalPadding
            anchors.topMargin: root.verticalPadding
            anchors.bottomMargin: root.verticalPadding
            text: root.text
            lines: root.lines
            list: root.list
            footer: root.footer
        }
    }
}
