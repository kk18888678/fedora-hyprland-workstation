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
    property int contentPadding: Theme.popupPadding
    // Omarchy's KeyboardPanel defaults are 280x200; feature panels normally
    // override width and fit height to their live content.
    property int popupWidth: 280
    property int popupHeight: 200
    property bool fitHeightToContent: false
    property Item contentSizingItem: null
    property int minPopupHeight: 0
    property int maxPopupHeight: 0
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
    readonly property var popupScreen: anchorWindow && anchorWindow.screen
        ? anchorWindow.screen
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    readonly property real screenW: root.screen ? root.screen.width : (popupScreen ? popupScreen.width : 0)
    readonly property real screenH: root.screen ? root.screen.height : (popupScreen ? popupScreen.height : 0)
    readonly property real barW: anchorWindow ? anchorWindow.width : 0
    readonly property real barH: anchorWindow ? anchorWindow.height : (bar ? bar.barSize : 0)
    readonly property var anchorTransform: anchorWindow ? anchorWindow.windowTransform : null
    readonly property int resolvedPopupWidth: Math.max(120, Theme.scaleGeometry(root.popupWidth))
    readonly property int resolvedPopupHeight: {
        var desired = Math.max(1, Theme.scaleGeometry(root.popupHeight))
        if (root.fitHeightToContent && root.contentSizingItem) {
            desired = root.contentSizingItem.implicitHeight + root.contentPadding * 2
        }
        if (root.minPopupHeight > 0) desired = Math.max(desired, root.minPopupHeight)
        if (root.maxPopupHeight > 0) desired = Math.min(desired, root.maxPopupHeight)
        return Math.max(1, Math.round(desired))
    }
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
        // The actual bar PanelWindow is the anchor window. Use its mapped
        // geometry directly; querying compositor layer state adds latency and
        // can fail closed when a popup is opened from a fresh session.
        var actualBarTop = 0
        var actualBarLeft = 0
        var actualBarWidth = barW
        var actualBarHeight = barH
        if (centerOnBar && (bar.position === "top" || bar.position === "bottom")) {
            x = screenW / 2 - root.resolvedPopupWidth / 2
            y = bar.position === "bottom"
                ? screenH - actualBarHeight - root.resolvedPopupHeight - margin
                : actualBarTop + actualBarHeight + margin
        } else if (centerOnBar) {
            x = bar.position === "left"
                ? actualBarLeft + actualBarWidth + margin
                : screenW - actualBarWidth - root.resolvedPopupWidth - margin
            y = screenH / 2 - root.resolvedPopupHeight / 2
        } else if (bar.position === "bottom") {
            x = anchorScreenPos.x + resolvedAnchorItem.width / 2 - root.resolvedPopupWidth / 2
            y = screenH - actualBarHeight - root.resolvedPopupHeight - margin
        } else if (bar.position === "left") {
            x = actualBarLeft + actualBarWidth + margin
            y = anchorScreenPos.y + resolvedAnchorItem.height / 2 - root.resolvedPopupHeight / 2
        } else if (bar.position === "right") {
            x = screenW - actualBarWidth - root.resolvedPopupWidth - margin
            y = anchorScreenPos.y + resolvedAnchorItem.height / 2 - root.resolvedPopupHeight / 2
        } else {
            x = anchorScreenPos.x + resolvedAnchorItem.width / 2 - root.resolvedPopupWidth / 2
            y = actualBarTop + actualBarHeight + margin
        }
        x = Math.max(margin, Math.min(x, screenW - root.resolvedPopupWidth - margin))
        y = Math.max(margin, Math.min(y, screenH - root.resolvedPopupHeight - margin))
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
            surfaceReady = true
            focusPrimed = false
            beginFocusPrime()
            Qt.callLater(function() { root.focusPanel() })
            if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root, ownerId)
        } else {
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
        width: root.resolvedPopupWidth
        height: root.resolvedPopupHeight
        z: 1
        radius: Theme.radiusLg
        color: Theme.popups.background
        border.color: Theme.popups.border
        border.width: Theme.borderWidthDefault
        visible: root.shown

        MouseArea {
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
        }

        FocusScope {
            id: contentScope
            anchors.fill: parent
            anchors.margins: root.contentPadding
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
