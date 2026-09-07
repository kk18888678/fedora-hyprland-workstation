import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"

// Omarchy-aligned keyboard-capable bar panel. The visible card is rendered in
// a full-screen layer-shell surface so the compositor can grant keyboard focus
// reliably; its position is still derived from the owning Aurelia bar/widget.
PanelWindow {
    id: root

    property var anchorItem: null
    property var bar: null
    property string ownerId: ""
    property bool shown: false
    property int margin: Theme.popupMargin
    property int popupWidth: 340
    property int popupHeight: 300
    property bool centerOnBar: false
    property var dismissHandler: null
    property var focusTarget: null
    property bool focusPrimed: false
    property bool surfaceReady: false
    property int surfaceX: 0
    property int surfaceY: 0
    property int surfaceWidth: 0
    property int surfaceHeight: 0
    property int surfaceRightGap: 0
    property int surfaceBottomGap: 0

    readonly property var resolvedAnchorItem: {
        var revision = bar ? bar.widgetRevision : 0
        if (bar && typeof bar.anchorItemFor === "function") {
            var slot = bar.anchorItemFor(ownerId)
            if (slot) return slot
        }
        return anchorItem
    }
    readonly property var anchorWindow: resolvedAnchorItem && resolvedAnchorItem.QsWindow && resolvedAnchorItem.QsWindow.window
        ? resolvedAnchorItem.QsWindow.window
        : (bar && bar.contentItem ? bar : null)
    readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
    readonly property real screenW: root.screen ? root.screen.width : (popupScreen ? popupScreen.width : 0)
    readonly property real screenH: root.screen ? root.screen.height : (popupScreen ? popupScreen.height : 0)
    readonly property real barW: anchorWindow ? anchorWindow.width : 0
    readonly property real barH: anchorWindow ? anchorWindow.height : (bar ? bar.barSize : 0)
    readonly property var anchorTransform: anchorWindow ? anchorWindow.windowTransform : null
    readonly property point anchorScreenPos: {
        // mapToItem() is one-shot. The bar layer query completes after
        // resident widget layout, so surfaceReady is the explicit reactive
        // invalidation equivalent to Omarchy's TransformWatcher.
        var geometryTick = root.surfaceReady
        var transform = anchorTransform
        if (!resolvedAnchorItem || !anchorWindow) return Qt.point(0, 0)
        return resolvedAnchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
    }
    readonly property point cardOrigin: {
        var transform = anchorTransform
        if (!resolvedAnchorItem || !bar || screenW <= 0 || screenH <= 0) return Qt.point(margin, margin)
        var x = 0
        var y = 0
        var actualBarTop = root.surfaceReady ? root.surfaceY : 0
        var actualBarLeft = root.surfaceReady ? root.surfaceX : 0
        var actualBarWidth = root.surfaceReady ? root.surfaceWidth : barW
        var actualBarHeight = root.surfaceReady ? root.surfaceHeight : barH
        if (centerOnBar && (bar.position === "top" || bar.position === "bottom")) {
            x = screenW / 2 - popupWidth / 2
            y = bar.position === "bottom"
                ? screenH - root.surfaceBottomGap - actualBarHeight - popupHeight - margin
                : actualBarTop + actualBarHeight + margin
        } else if (centerOnBar) {
            x = bar.position === "left"
                ? actualBarLeft + actualBarWidth + margin
                : screenW - root.surfaceRightGap - actualBarWidth - popupWidth - margin
            y = screenH / 2 - popupHeight / 2
        } else if (bar.position === "bottom") {
            x = anchorScreenPos.x + resolvedAnchorItem.width / 2 - popupWidth / 2
            y = screenH - root.surfaceBottomGap - actualBarHeight - popupHeight - margin
        } else if (bar.position === "left") {
            x = actualBarLeft + actualBarWidth + margin
            y = anchorScreenPos.y + resolvedAnchorItem.height / 2 - popupHeight / 2
        } else if (bar.position === "right") {
            x = screenW - root.surfaceRightGap - actualBarWidth - popupWidth - margin
            y = anchorScreenPos.y + resolvedAnchorItem.height / 2 - popupHeight / 2
        } else {
            x = anchorScreenPos.x + resolvedAnchorItem.width / 2 - popupWidth / 2
            y = actualBarTop + actualBarHeight + margin
        }
        x = Math.max(margin, Math.min(x, screenW - popupWidth - margin))
        y = Math.max(margin, Math.min(y, screenH - popupHeight - margin))
        return Qt.point(Math.round(x), Math.round(y))
    }

    default property alias contentItem: contentHolder.children

    screen: popupScreen
    visible: shown && resolvedAnchorItem !== null && anchorWindow !== null && bar !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-keyboard-panel"
    WlrLayershell.keyboardFocus: shown
        ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
        : WlrKeyboardFocus.None

    function dismiss() {
        if (typeof root.dismissHandler === "function") root.dismissHandler()
        else root.shown = false
    }

    function focusPanel() {
        var target = root.focusTarget || contentScope
        if (root.visible && target && typeof target.forceActiveFocus === "function") target.forceActiveFocus()
    }

    function beginFocusPrime() {
        if (shown) focusPrimeTimer.restart()
    }

    onShownChanged: {
        if (shown) {
            surfaceReady = false
            geometryProcess.running = true
            focusPrimed = false
            beginFocusPrime()
            Qt.callLater(function() { root.focusPanel() })
            if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root, ownerId)
        } else {
            geometryProcess.running = false
            surfaceReady = false
            focusPrimeTimer.stop()
            focusPrimed = false
            if (bar && typeof bar.releasePopout === "function") bar.releasePopout(root)
        }
    }

    onBarChanged: if (shown && bar && typeof bar.requestPopout === "function") bar.requestPopout(root, ownerId)
    onAnchorItemChanged: if (shown) Qt.callLater(function() { root.focusPanel() })

    Timer {
        id: focusPrimeTimer
        interval: 75
        repeat: false
        onTriggered: {
            if (root.shown) {
                root.focusPrimed = true
                root.focusPanel()
            }
        }
    }

    Item {
        width: 0
        height: 0
        visible: true

        Process {
            id: geometryProcess
            command: ["/usr/bin/timeout", "--kill-after=1s", "2s", "/usr/bin/hyprctl", "layers", "-j"]
            stdout: StdioCollector { id: geometryStdout }
            stderr: StdioCollector { id: geometryStderr }

            onExited: function(code) {
                if (code !== 0) {
                    console.error("[POPUP] bar_geometry_failed owner=" + root.ownerId + " code=" + code + " error=" + geometryStderr.text.trim())
                    return
                }
                try {
                    var payload = JSON.parse(geometryStdout.text || "{}")
                    var found = null
                    function visit(value) {
                        if (found || value === null || value === undefined) return
                        if (Array.isArray(value)) {
                            for (var i = 0; i < value.length; i++) visit(value[i])
                            return
                        }
                        if (typeof value !== "object") return
                        if (String(value.namespace || "") === "aurelia-bar" &&
                            Number.isFinite(Number(value.x)) && Number.isFinite(Number(value.y)) &&
                            Number.isFinite(Number(value.w)) && Number.isFinite(Number(value.h))) {
                            found = value
                            return
                        }
                        for (var key in value) visit(value[key])
                    }
                    visit(payload)
                    if (!found) {
                        console.error("[POPUP] bar_geometry_missing owner=" + root.ownerId)
                        return
                    }
                    root.surfaceX = Math.round(Number(found.x))
                    root.surfaceY = Math.round(Number(found.y))
                    root.surfaceWidth = Math.round(Number(found.w))
                    root.surfaceHeight = Math.round(Number(found.h))
                    root.surfaceRightGap = root.screenW - root.surfaceX - root.surfaceWidth
                    root.surfaceBottomGap = root.screenH - root.surfaceY - root.surfaceHeight
                    root.surfaceReady = true
                    console.info("[POPUP] bar_geometry owner=" + root.ownerId + " rect=" + root.surfaceX + "," + root.surfaceY + " " + root.surfaceWidth + "x" + root.surfaceHeight)
                    console.info("[POPUP] card_geometry owner=" + root.ownerId + " anchor=" + root.anchorScreenPos.x + "," + root.anchorScreenPos.y + " origin=" + root.cardOrigin.x + "," + root.cardOrigin.y)
                } catch (error) {
                    console.error("[POPUP] bar_geometry_invalid owner=" + root.ownerId + " error=" + error)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        enabled: root.shown
        acceptedButtons: Qt.AllButtons
        onClicked: function(mouse) {
            mouse.accepted = true
            root.dismiss()
        }
    }

    Rectangle {
        id: card
        x: root.cardOrigin.x
        y: root.cardOrigin.y
        width: root.popupWidth
        height: root.popupHeight
        z: 1
        radius: Theme.radiusLg
        color: Theme.bgBase
        border.color: Theme.border
        border.width: Theme.borderWidthDefault
        visible: root.surfaceReady && root.shown

        MouseArea {
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
        }

        FocusScope {
            id: contentScope
            anchors.fill: parent
            anchors.margins: Theme.popupPadding
            focus: root.shown
            z: 1

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    console.info("[POPUP] escape owner=" + root.ownerId)
                    root.dismiss()
                    event.accepted = true
                }
            }

            Item {
                id: contentHolder
                anchors.fill: parent
            }
        }
    }
}
