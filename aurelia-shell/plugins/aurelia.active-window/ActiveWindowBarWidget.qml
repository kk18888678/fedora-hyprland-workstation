import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../theme"
import "../../ui"
import "../../services/WindowRouting.js" as WindowRouting

// Active-window label for the bar. State comes from the compositor's active
// toplevel signal, never from a polling timer or a shell subprocess. The
// widget hides on vertical bars and when no title/app identity is available.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.active-window"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    // The override seam is unused in production. It lets the isolated QML
    // fixture drive this exact widget with a deterministic toplevel object
    // without connecting to or mutating the live compositor.
    property var activeToplevelOverride

    readonly property var activeToplevel: root.activeToplevelOverride !== undefined
        ? root.activeToplevelOverride : Hyprland.activeToplevel
    readonly property var routeInfo: WindowRouting.workspaceRouteInfo(root.activeToplevel)
    readonly property string appId: {
        var handle = root.activeToplevel ? root.activeToplevel.handle : null
        if (handle && handle.appId) return String(handle.appId)
        return String(root.routeInfo.appId || "")
    }
    // The desktop entry supplies both the application artwork and its name.
    // Resolve it once and reuse it so the icon and the label can never
    // disagree about which application they describe. Unknown applications
    // resolve to null and fall back below. The count keeps the lookup reactive
    // to the asynchronous desktop-entry scan, which can finish after the
    // widget is first bound (a plain heuristicLookup is not reactive).
    readonly property int desktopEntryCount: DesktopEntries.applications.values.length
    readonly property var appEntry: {
        var entryCount = root.desktopEntryCount
        if (root.appId === "") return null
        return DesktopEntries.heuristicLookup(root.appId)
    }
    // Display mode defaults to the application name. Anything that is not an
    // explicit "title" fails closed to "app", so an unknown or absent setting
    // can never hide the label.
    readonly property string displayMode: {
        var raw = root.settings && root.settings.displayMode !== undefined
            ? String(root.settings.displayMode).toLowerCase() : ""
        return raw === "title" ? "title" : "app"
    }
    // Historical title-first identity: title wins, then the Wayland app id,
    // then the XWayland class reported by the compositor's IPC object. Keep
    // every step null-safe.
    readonly property string titleLabel: {
        var title = String(root.activeToplevel && root.activeToplevel.title
            ? root.activeToplevel.title : "").trim()
        if (title !== "") return title
        var handle = root.activeToplevel ? root.activeToplevel.handle : null
        var handleAppId = handle && handle.appId ? String(handle.appId) : ""
        if (handleAppId !== "") return handleAppId
        return String(root.routeInfo.className || root.routeInfo.initialClass || "")
    }
    // Application-name identity. The desktop entry's own name is authoritative
    // (upstream does not title-case consistently: foot ships "Foot" while kitty
    // ships "kitty"), then the app id, then the compositor's class.
    readonly property string appName: {
        var name = root.appEntry && root.appEntry.name ? String(root.appEntry.name).trim() : ""
        if (name !== "") return name
        if (root.appId !== "") return root.appId
        return String(root.routeInfo.className || root.routeInfo.initialClass || "")
    }
    // The rendered label follows the configured display mode. The tooltip
    // binds to `label`, so title mode still exposes the full, un-elided title
    // while app mode names the application.
    readonly property string label: root.displayMode === "title" ? root.titleLabel : root.appName
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text
    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    readonly property int iconCanvas: root.bar && root.bar.barIconCanvas
        ? root.bar.barIconCanvas : 16
    readonly property real textMargin: root.bar && root.bar.barTextMargin !== undefined
        ? root.bar.barTextMargin : Theme.bar.textMargin
    readonly property int textSize: root.bar && root.bar.barTextSize
        ? root.bar.barTextSize : Theme.bar.text
    readonly property int iconSpacing: Theme.spacingXs

    // The manifest default is 280 px. A user-provided value is bounded so a
    // bad inline setting can never make the bar layout unbounded.
    readonly property int maxWidth: {
        var raw = root.settings && root.settings.maxWidth !== undefined
            ? parseInt(root.settings.maxWidth) : 280
        if (isNaN(raw) || raw < 80) return 280
        return Math.min(raw, 800)
    }
    // The desktop entry supplies the application artwork. Unknown applications
    // and missing or invalid icons fall back the same way the task list does,
    // with a generic executable icon as the final resort.
    readonly property string desktopIconName: {
        var entry = root.appEntry
        return entry && entry.icon ? String(entry.icon) : ""
    }
    // The isolated fixture can pin the resolved icon name so the symbolic-icon
    // colour policy is exercised deterministically without a live icon-theme
    // lookup. The override is unused in production.
    property var iconNameOverride
    readonly property string iconName: {
        if (root.iconNameOverride !== undefined) return String(root.iconNameOverride)
        if (root.desktopIconName !== "") return root.desktopIconName
        var normalized = root.appId.toLowerCase()
        if (normalized.indexOf("chatgpt") >= 0) return "chatgpt"
        if (normalized.indexOf("chrom") >= 0) return "chromium"
        if (normalized.indexOf("kate") >= 0) return "kate"
        if (normalized.indexOf("foot") >= 0) return "utilities-terminal"
        return "application-x-executable"
    }
    // The isolated fixture can force an empty source so the no-icon slot-hide
    // path is exercised without depending on a live icon-theme lookup. The
    // override is unused in production.
    property var iconSourceOverride
    readonly property string iconSource: root.iconSourceOverride !== undefined
        ? String(root.iconSourceOverride)
        : Quickshell.iconPath(root.iconName, "application-x-executable")
    // A resolved icon keeps the shared tray-sized image ink so the artwork has
    // the same visual mass as a peer bar glyph, while the slot stays the icon
    // canvas so the layout rhythm and hit area do not change.
    readonly property int trayIcon: root.bar && root.bar.barTrayIcon
        ? root.bar.barTrayIcon : Theme.bar.trayIcon
    readonly property bool hasIcon: root.iconSource !== ""

    // Real application logos are multi-colour artwork, but the shared icon
    // primitive colorizes with Qt's luminance-multiplied duotone, which
    // collapses every logo onto a monochrome ramp of the tint. Only genuine
    // symbolic masks (an icon name ending in "-symbolic", ignoring any query
    // string) may keep that tint. This mirrors the tray's isSymbolicIcon
    // contract so both surfaces treat real logos the same way.
    readonly property bool symbolicIcon: {
        var name = String(root.iconName || "").split("?")[0]
        return name.slice(-9) === "-symbolic"
    }

    // Isolated-fixture seam: the rendered icon ink/slot and label metrics. The
    // production bar never reads these; they let the QML runtime test assert
    // the rendered geometry without re-implementing the layout.
    readonly property real iconInkSize: windowIcon.width
    readonly property real iconSlotSize: iconSlot.width
    readonly property bool iconSlotVisible: iconSlot.visible
    readonly property bool iconPreservesColors: windowIcon.preserveColors
    readonly property real labelOpacity: labelText.opacity
    readonly property real visibleLabelWidth: labelText.width

    readonly property real measuredLabelWidth: labelMetrics.advanceWidth
    readonly property real labelWidth: Math.min(root.measuredLabelWidth + root.textMargin * 2, root.maxWidth)
    property real animatedLabelWidth: root.labelWidth
    Behavior on animatedLabelWidth {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    visible: !root.vertical && root.label !== ""
    implicitWidth: root.visible
        ? (root.hasIcon ? root.iconCanvas + root.iconSpacing : 0)
            + Math.max(0, root.animatedLabelWidth)
        : 0
    implicitHeight: root.bar ? root.bar.barSize : 26

    function activeHandle() {
        var toplevel = root.activeToplevel
        return toplevel && toplevel.handle ? toplevel.handle : null
    }

    function activateWindow() {
        var handle = root.activeHandle()
        if (handle && typeof handle.activate === "function") {
            handle.activate()
            return "ok"
        }
        return "not-available"
    }

    function closeWindow() {
        var handle = root.activeHandle()
        if (handle && typeof handle.close === "function") {
            handle.close()
            return "ok"
        }
        return "not-available"
    }

    TextMetrics {
        id: labelMetrics
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize
        text: root.label
    }

    Rectangle {
        id: hoverFill
        anchors.fill: parent
        radius: Theme.radiusSm
        color: pointerHover.hovered ? Theme.selection : "transparent"
    }

    HoverHandler {
        id: pointerHover
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.iconSpacing

        Item {
            id: iconSlot
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconCanvas
            height: root.iconCanvas
            visible: root.hasIcon

            AureliaIcon {
                id: windowIcon
                anchors.centerIn: parent
                width: root.trayIcon
                height: root.trayIcon
                iconSize: root.trayIcon
                name: ""
                sourcePath: root.iconSource
                preserveColors: !root.symbolicIcon
                tint: root.barForeground
            }
        }

        Text {
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, root.animatedLabelWidth - root.textMargin * 2)
            text: root.label
            color: root.barForeground
            font.family: Theme.fontFamily
            font.pixelSize: root.textSize
            font.weight: Theme.fontWeightMedium
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            clip: true
            verticalAlignment: Text.AlignVCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            mouse.accepted = true
            if (mouse.button === Qt.LeftButton) root.activateWindow()
            else root.closeWindow()
        }
    }

    AureliaToolTip {
        triggerItem: root
        bar: root.bar
        hovered: pointerHover.hovered
        text: root.label
    }
}
