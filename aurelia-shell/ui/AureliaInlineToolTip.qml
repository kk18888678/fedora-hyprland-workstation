import QtQuick
import "../theme"

// In-scene tooltip host for use INSIDE an already-open surface (the agents
// panel). It renders the shared AureliaToolTipContent body with the same
// Theme.tooltip.* visuals and the same 400 ms delay as the PopupWindow host,
// but it is a plain Item positioned inside its parent. That keeps it testable
// offscreen (a PopupWindow cannot be rendered by the fixture) and avoids
// nesting a popup inside the keyboard-grabbing layer-shell panel.
//
// It is placed below its trigger and flips above when it would overflow the
// parent's own bounds, then clamps to those bounds.
Item {
    id: root

    property var triggerItem: null
    property string text: ""
    property var lines: []
    property var list: []
    property var footer: null
    property bool hovered: false
    property int delay: 400
    property int margin: 6
    property int maxTextWidth: 300
    property int horizontalPadding: Theme.spacingSm + 2
    property int verticalPadding: Theme.spacingXs + 3
    property bool revealed: false

    readonly property bool hasContent: text !== "" ||
        (Array.isArray(lines) && lines.length > 0) ||
        (Array.isArray(list) && list.length > 0) ||
        (footer !== null && footer !== undefined && String(footer.text || "") !== "")
    // Exposed for the offscreen probe so it can assert every rendered line
    // uses the theme's tooltip text colour.
    readonly property color textColor: Theme.tooltip.text
    readonly property color backgroundColor: Theme.tooltip.background

    width: tooltipBody.implicitWidth + horizontalPadding * 2
    height: tooltipBody.implicitHeight + verticalPadding * 2
    visible: revealed && hasContent
    z: 1000

    function dismiss() {
        revealed = false
        showTimer.stop()
    }

    function reveal() {
        if (!root.hovered || !root.hasContent || root.triggerItem === null) return
        root.revealed = true
    }

    // Place inside the parent's own bounds: below the trigger by default,
    // flipped above when that would overflow, then clamped on both axes.
    function reposition() {
        if (!root.triggerItem || !root.parent) return
        var origin = root.triggerItem.mapToItem(root.parent, 0, 0)
        var boundsWidth = Number(root.parent.width) || 0
        var boundsHeight = Number(root.parent.height) || 0
        var localX = origin.x + root.triggerItem.width / 2 - root.width / 2
        var localY = origin.y + root.triggerItem.height + root.margin
        if (localY + root.height > boundsHeight - root.margin)
            localY = origin.y - root.height - root.margin
        localX = Math.max(root.margin,
            Math.min(localX, boundsWidth - root.width - root.margin))
        localY = Math.max(root.margin,
            Math.min(localY, boundsHeight - root.height - root.margin))
        root.x = Math.round(localX)
        root.y = Math.round(localY)
    }

    onHoveredChanged: {
        if (hovered) showTimer.restart()
        else dismiss()
    }

    onTriggerItemChanged: {
        if (root.hovered && root.triggerItem !== null) showTimer.restart()
    }

    onLinesChanged: {
        if (root.hovered) showTimer.restart()
    }

    onRevealedChanged: {
        if (root.revealed) root.reposition()
    }

    onWidthChanged: if (root.revealed) root.reposition()
    onHeightChanged: if (root.revealed) root.reposition()

    Timer {
        id: showTimer
        interval: root.delay
        repeat: false
        onTriggered: root.reveal()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Theme.tooltip.background
        border.color: Theme.tooltip.border
        border.width: Theme.borderWidthDefault

        AureliaToolTipContent {
            id: tooltipBody
            objectName: "tooltipContent"
            anchors.fill: parent
            anchors.leftMargin: root.horizontalPadding
            anchors.rightMargin: root.horizontalPadding
            anchors.topMargin: root.verticalPadding
            anchors.bottomMargin: root.verticalPadding
            text: root.text
            lines: root.lines
            list: root.list
            footer: root.footer
            maxTextWidth: root.maxTextWidth
        }
    }
}
