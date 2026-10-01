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

    // Opt-in, bounded observability for the bar tooltip lifecycle. Strictly
    // gated on AURELIA_TOOLTIP_DEBUG=1 and a complete no-op without it (every
    // helper returns immediately). The in-scene panel host cannot render offscreen
    // against a live bar, so this is the permanent diagnosis channel for an
    // open-then-close in the field.
    readonly property bool tooltipDebugEnabled:
        Quickshell.env("AURELIA_TOOLTIP_DEBUG") === "1"
    readonly property string contentKind: {
        if (Array.isArray(list) && list.length > 0) return "list"
        if (Array.isArray(lines) && lines.length > 0) return "lines"
        if (text !== "") return "text"
        if (footer !== null && footer !== undefined &&
            String(footer.text || "") !== "") return "footer"
        return "none"
    }
    readonly property int contentLength: {
        if (Array.isArray(list) && list.length > 0) return list.length
        if (Array.isArray(lines) && lines.length > 0) return lines.length
        if (text !== "") return String(text).length
        if (footer !== null && footer !== undefined) return String(footer.text || "").length
        return 0
    }
    function tooltipLog(event) {
        if (!root.tooltipDebugEnabled) return
        // console.info (not console.log) so the line survives Quickshell's
        // default log level as `INFO qml: [TOOLTIP] ...`.
        console.info("[TOOLTIP] " + event +
            " hovered=" + root.hovered +
            " revealed=" + root.revealed +
            " visible=" + root.visible +
            " backingWindowVisible=" + root.backingWindowVisible +
            " implicitWidth=" + Math.round(root.implicitWidth) +
            " implicitHeight=" + Math.round(root.implicitHeight) +
            " kind=" + root.contentKind +
            " length=" + root.contentLength)
    }

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
    // The tooltip is a pure overlay: it must NEVER take pointer input. If it
    // did, a popup that mapped under the cursor would make the trigger lose
    // hover, which dismissed the tooltip, which let the pointer re-enter the
    // trigger and reopen it: an open/close flicker loop. An empty input region
    // makes the surface click-through, so hovering the icon can never be
    // interrupted by the tooltip that is describing it. Rendering is
    // unaffected; the input region is not a visual clip.
    mask: Region {}
    // Floored so a transiently-degenerate content measurement can never hand
    // Quickshell a zero-sized popup (ProxyPopupWindow deletes its backing
    // window whenever it becomes momentarily non-visible).
    implicitWidth: Math.max(1, tooltipBody.implicitWidth + horizontalPadding * 2)
    implicitHeight: Math.max(1, tooltipBody.implicitHeight + verticalPadding * 2)

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
        root.tooltipLog("hovered")
    }

    onRevealedChanged: root.tooltipLog("revealed")
    onVisibleChanged: root.tooltipLog("visible")
    onImplicitWidthChanged: root.tooltipLog("implicitWidth")
    onImplicitHeightChanged: root.tooltipLog("implicitHeight")
    onBackingWindowVisibleChanged: root.tooltipLog("backingWindowVisible")

    onTextChanged: {
        if (root.hovered && !root.revealed) showTimer.restart()
    }

    onLinesChanged: {
        if (root.hovered && !root.revealed) showTimer.restart()
    }

    onListChanged: {
        // A visible tooltip must not be perturbed by a data refresh: the
        // reveal timer is only meaningful before the first reveal.
        if (root.hovered && !root.revealed) showTimer.restart()
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
            root.tooltipLog("anchoring rect=" + tooltipAnchor.rect.x + "," +
                tooltipAnchor.rect.y + "," + tooltipAnchor.rect.width + "x" +
                tooltipAnchor.rect.height)
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
