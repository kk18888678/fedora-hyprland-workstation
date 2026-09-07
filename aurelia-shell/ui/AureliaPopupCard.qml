import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../theme"

// Omarchy-style bar-owned popout primitive. The owning bar widget supplies the
// actual trigger item; this surface never guesses a monitor coordinate and
// never uses a timer to wait for a layer-shell rectangle.
PopupWindow {
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

    readonly property var anchorWindow: anchorItem && anchorItem.QsWindow && anchorItem.QsWindow.window
        ? anchorItem.QsWindow.window
        : (bar && bar.contentItem ? bar : null)

    // Match the reference implementation: popup content is a child of the
    // card's inset holder, not an arbitrary QObject in Item.data.
    default property alias contentItem: contentHolder.children

    // An unanchored PopupWindow is unsafe: Qt may place it at the screen
    // origin, which can cover the bar. Omarchy keeps the card unavailable
    // until the owning bar item has a real QsWindow.
    visible: shown && root.anchorItem !== null && root.anchorWindow !== null && root.bar !== null
    color: "transparent"
    implicitWidth: popupWidth
    implicitHeight: popupHeight

    function syncPopoutOwnership() {
        if (!bar) return
        if (shown && root.anchorItem !== null && root.anchorWindow !== null) {
            if (typeof bar.requestPopout === "function") bar.requestPopout(root, ownerId)
        } else if (typeof bar.releasePopout === "function") {
            bar.releasePopout(root)
        }
    }

    onBarChanged: syncPopoutOwnership()
    onAnchorItemChanged: syncPopoutOwnership()
    onAnchorWindowChanged: syncPopoutOwnership()

    function focusKeyboardScope() {
        if (root.visible) contentScope.forceActiveFocus()
    }

    onShownChanged: {
        syncPopoutOwnership()
        if (shown) console.info("[POPUP] open owner=" + root.ownerId + " anchored=" + (root.anchorItem !== null && root.anchorWindow !== null))
        if (shown) Qt.callLater(function() { root.focusKeyboardScope() })
    }

    Component.onCompleted: {
        if (shown && (root.anchorItem === null || root.anchorWindow === null)) {
            console.warn("[POPUP] anchor_unavailable owner=" + ownerId)
        }
    }

    function dismiss() {
        if (typeof root.dismissHandler === "function") root.dismissHandler()
        else root.shown = false
    }

    HyprlandFocusGrab {
        active: root.visible
        windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
        onCleared: root.dismiss()
    }

    anchor {
        id: popupAnchor
        window: root.anchorWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
            if (!root.anchorItem || !root.anchorWindow || !root.bar) return
            var target = root.anchorItem
            var localX = target.width / 2 - root.implicitWidth / 2
            var localY = target.height + root.margin
            if (root.bar.position === "bottom") {
                localY = -root.implicitHeight - root.margin
            } else if (root.bar.position === "left") {
                localX = target.width + root.margin
                localY = target.height / 2 - root.implicitHeight / 2
            } else if (root.bar.position === "right") {
                localX = -root.implicitWidth - root.margin
                localY = target.height / 2 - root.implicitHeight / 2
            }

            var point = root.anchorWindow.contentItem.mapFromItem(target, localX, localY)

            if (root.centerOnBar) {
                var centerX = 0
                var centerY = 0
                if (root.bar.position === "top" || root.bar.position === "bottom") {
                    centerX = root.anchorWindow.width / 2 - root.implicitWidth / 2
                    centerY = root.bar.position === "bottom"
                        ? -root.implicitHeight - root.margin
                        : root.anchorWindow.height + root.margin
                    centerX = Math.max(root.margin, Math.min(centerX, root.anchorWindow.width - root.implicitWidth - root.margin))
                } else {
                    centerX = root.bar.position === "left"
                        ? root.anchorWindow.width + root.margin
                        : -root.implicitWidth - root.margin
                    centerY = root.anchorWindow.height / 2 - root.implicitHeight / 2
                    centerY = Math.max(root.margin, Math.min(centerY, root.anchorWindow.height - root.implicitHeight - root.margin))
                }
                popupAnchor.rect.x = Math.round(centerX)
                popupAnchor.rect.y = Math.round(centerY)
                return
            }

            if (root.bar.position === "top" || root.bar.position === "bottom") {
                point.x = Math.max(root.margin, Math.min(point.x, root.anchorWindow.width - root.implicitWidth - root.margin))
            } else {
                point.y = Math.max(root.margin, Math.min(point.y, root.anchorWindow.height - root.implicitHeight - root.margin))
            }
            popupAnchor.rect.x = Math.round(point.x)
            popupAnchor.rect.y = Math.round(point.y)
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Theme.bgBase
        border.color: Theme.border
        border.width: Theme.borderWidthDefault

        FocusScope {
            id: contentScope
            anchors.fill: parent
            focus: root.visible

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
                anchors.margins: Theme.popupPadding
            }
        }
    }
}
