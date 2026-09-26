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
    // The override seams are unused in production. They let the isolated QML
    // fixture drive this exact widget with a deterministic toplevel object and
    // toplevel model without connecting to or mutating the live compositor.
    property var activeToplevelOverride
    property var toplevelsOverride

    // The bar's compositor source is derived reactively. Hyprland.activeToplevel
    // is authoritative once its activewindowv2 signal has arrived, but it is
    // null for an unbounded time when the shell starts or reloads while a
    // window is already focused. The fallback recovers the focused toplevel
    // from the compositor's toplevel model, which refreshToplevels() populates
    // independently of that event. It fails closed to null when the model
    // offers no unambiguous focused entry, so the widget remains hidden rather
    // than naming the wrong window. The binding is reactive, so the fallback
    // appears as soon as the model is available and gives way to the real
    // signal when the event finally arrives.
    readonly property var toplevelValues: root.toplevelsOverride !== undefined
        ? root.toplevelsOverride
        : (Hyprland.toplevels ? Hyprland.toplevels.values : null)
    readonly property var activeToplevel: {
        if (root.activeToplevelOverride !== undefined) return root.activeToplevelOverride
        if (Hyprland.activeToplevel) return Hyprland.activeToplevel
        return WindowRouting.focusedToplevel(root.toplevelValues)
    }
    readonly property var routeInfo: WindowRouting.workspaceRouteInfo(root.activeToplevel)
    readonly property string appId: {
        var handle = root.activeToplevel ? root.activeToplevel.handle : null
        if (handle && handle.appId) return String(handle.appId)
        if (root.routeInfo.appId) return String(root.routeInfo.appId)
        // The model-derived fallback toplevel often has an empty handle.appId
        // because the wlr handle is not linked yet, so the compositor's IPC
        // class is the reliable identity in that window.
        return String(root.routeInfo.className || root.routeInfo.initialClass || "")
    }
    // The desktop entry supplies both the application artwork and its name.
    // Resolve it once and reuse it so the icon and the label can never
    // disagree about which application they describe. Unknown applications
    // resolve to null and fall back below. The count keeps the lookup reactive
    // to the asynchronous desktop-entry scan, which can finish after the
    // widget is first bound (a plain heuristicLookup is not reactive). The
    // lookup itself is synchronous and, on a pathologically large database,
    // can block briefly; the raw app id/class label and an interim theme or
    // generic icon are derived independently, so the widget never disappears
    // while that scan resolves.
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
        // Prefer the raw application id when the icon theme provides it
        // directly. This is a real icon lookup, not a placeholder, and it
        // resolves ids such as foot, chromium-browser, firefox, kitty, vscode,
        // co.anysphere.cursor, org.gnome.Nautilus and chatgpt that the
        // substring heuristics below would otherwise flatten to a generic
        // executable glyph. It has no effect when the theme lacks the id, so
        // the heuristics and final fallback still run.
        if (root.appId !== "" && Quickshell.hasThemeIcon(root.appId)) return root.appId
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

    // The label geometry is measured by a hidden, non-eliding Text that copies
    // the visible label's exact font and render type. A separate TextMetrics
    // cannot be guaranteed to match the rendered width: it has no renderType
    // property and must restate the font by hand, so omitting (for example)
    // the weight makes Qt's ElideRight drop a character onto an ellipsis even
    // when the box is only sub-pixel too small. A real Text with the same
    // engine means the metric and the render always agree, and the metric
    // re-flows automatically if the resolved font changes later. The measurer
    // must never elide: an elided Text reports only its elided width, which
    // would shrink the box on every pass (a feedback loop).
    readonly property real measuredLabelWidth: labelMeasure.contentWidth
    // Rendered geometry, read by the isolated fixture only. `renderTruncated`
    // is Qt's authoritative signal that ElideRight actually dropped text; the
    // content-width comparison is kept as a secondary signal.
    readonly property real renderContentWidth: labelText.contentWidth
    readonly property bool renderTruncated: labelText.truncated
    readonly property bool renderElided: root.renderTruncated
        || root.renderContentWidth > root.visibleLabelWidth + 0.001
    readonly property real labelWidth: Math.min(root.measuredLabelWidth + root.textMargin * 2, root.maxWidth)
    property real animatedLabelWidth: root.labelWidth
    // The first non-empty label (the startup fallback resolving) must adopt
    // its final width immediately. Animating from the empty width makes the
    // widget slide open for no reason on shell start or reload. The label
    // metric can settle across several synchronous binding updates within
    // that one population, so the gate is released only after the current
    // event-loop turn rather than on the first width change. Every later
    // label change then keeps the 180 ms OutCubic transition.
    property bool labelWidthInitialized: false
    Behavior on animatedLabelWidth {
        enabled: root.labelWidthInitialized
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    onLabelChanged: {
        if (!root.labelWidthInitialized && root.label !== "")
            Qt.callLater(function() { root.labelWidthInitialized = true })
    }
    Component.onCompleted: {
        if (!root.labelWidthInitialized && root.label !== "")
            Qt.callLater(function() { root.labelWidthInitialized = true })
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
            font.family: Theme.fontFamilyResolved
            font.pixelSize: root.textSize
            font.weight: Theme.fontWeightMedium
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            clip: true
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Hidden, non-eliding measurer for the label. It is a real Text, not a
    // TextMetrics, so it uses the same engine (including renderType) and the
    // exact resolved font as the visible label; the metric therefore matches
    // the render and cannot drift. It carries no width and no elide, so
    // contentWidth is the natural, full-label width.
    Text {
        id: labelMeasure
        visible: false
        text: root.label
        font: labelText.font
        renderType: labelText.renderType
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
