import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../ui"
import "../../services"

// A bounded single-frame preview of one Hyprland toplevel. Live video is
// deliberately avoided: opening the overview should not create a permanent
// capture stream for every window on the desktop.
Item {
    id: root

    property var hyprlandToplevel: null
    property bool active: false
    property int captureAttempts: 0
    property int managerRevision: 0

    readonly property var directToplevel: root.hyprlandToplevel
        ? root.hyprlandToplevel.wayland
        : null
    readonly property var hyprlandHandle: root.hyprlandToplevel
        ? root.hyprlandToplevel.handle
        : null
    readonly property string appId: root.hyprlandHandle && root.hyprlandHandle.appId
        ? String(root.hyprlandHandle.appId)
        : ""
    readonly property string windowTitle: root.hyprlandToplevel && root.hyprlandToplevel.title
        ? String(root.hyprlandToplevel.title)
        : "Application"
    readonly property var appEntry: {
        var scan = root.desktopEntryCount
        var id = root.appId
        return id !== "" ? DesktopEntries.heuristicLookup(id) : null
    }
    // The desktop-entry scan is asynchronous; referencing its count keeps the
    // per-window lookup reactive so an icon appears once the scan completes.
    readonly property int desktopEntryCount: DesktopEntries.applications.values.length
    // The shared AppIconResolver owns the ordered icon chain and the
    // symbolic-versus-logo rule. The preview supplies only the identity it
    // holds: the desktop entry's Icon= as the app-icon hint and the compositor
    // app id as the in-flight window origin. Resolution is recomputed from
    // change handlers rather than a function-binding so the shared FileView
    // probe cannot create a binding dependency on its own caches.
    property var iconResolution: ({ source: "", name: "", symbolic: false, kind: "default", origin: "default" })
    function refreshIconResolution() {
        root.iconResolution = AppIconResolver.resolve({
            appIcon: root.appEntry && root.appEntry.icon ? String(root.appEntry.icon) : "",
            desktopEntry: root.appId,
            appName: root.appEntry && root.appEntry.name ? String(root.appEntry.name) : root.appId,
            origin: { appId: root.appId, className: root.appId }
        })
    }
    readonly property string iconSource: String(root.iconResolution.source || "")
    readonly property bool symbolicIcon: root.iconResolution.symbolic === true
    readonly property bool iconPreservesColors: windowIcon.preserveColors
    onAppIdChanged: root.refreshIconResolution()
    onAppEntryChanged: root.refreshIconResolution()
    Connections {
        target: AppIconResolver
        function onMetadataIndexRevisionChanged() { root.refreshIconResolution() }
    }

    // Hyprland can publish the IPC client before the foreign-toplevel object
    // is associated with it. Resolve that short race through the compositor's
    // native ToplevelManager instead of abandoning the preview permanently.
    readonly property var captureToplevel: {
        var revision = root.managerRevision
        if (root.directToplevel) return root.directToplevel

        var app = root.appId.toLowerCase()
        var title = root.windowTitle.toLowerCase()
        var values = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
        var appMatch = null
        for (var i = 0; i < values.length; i++) {
            var candidate = values[i]
            var candidateApp = candidate && candidate.appId ? String(candidate.appId).toLowerCase() : ""
            var candidateTitle = candidate && candidate.title ? String(candidate.title).toLowerCase() : ""
            if (app !== "" && candidateApp === app && title !== "" && candidateTitle === title)
                return candidate
            if (!appMatch && app !== "" && candidateApp === app) appMatch = candidate
        }
        return appMatch
    }
    readonly property real sourceAspectRatio: captureView.hasContent && captureView.sourceSize.height > 0
        ? captureView.sourceSize.width / captureView.sourceSize.height
        : (16 / 9)

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() {
            root.managerRevision++
        }
    }

    function requestFrame() {
        if (!root.active || !root.captureToplevel || !captureView) return
        Qt.callLater(function() {
            if (!root.active || !captureView.captureSource || captureView.hasContent) return
            captureView.captureFrame()
            if (root.captureAttempts < 8) {
                root.captureAttempts++
                captureRetry.restart()
            }
        })
    }

    onActiveChanged: {
        captureRetry.stop()
        root.captureAttempts = 0
        if (root.active) root.requestFrame()
    }

    onCaptureToplevelChanged: {
        captureRetry.stop()
        root.captureAttempts = 0
        root.requestFrame()
    }

    Rectangle {
        id: previewSurface
        anchors.fill: parent
        radius: Theme.radiusSm
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
        border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.38)
        border.width: Theme.borderWidthDefault
        clip: true

        ScreencopyView {
            id: captureView
            anchors.centerIn: parent
            width: Math.min(parent.width, height * root.sourceAspectRatio)
            height: Math.min(parent.height, parent.width / root.sourceAspectRatio)
            captureSource: root.active ? root.captureToplevel : null
            live: false
            paintCursor: false
            constraintSize: Qt.size(Math.max(1, parent.width), Math.max(1, parent.height))
            visible: root.active && hasContent

            onCaptureSourceChanged: root.requestFrame()
            onHasContentChanged: if (hasContent) captureRetry.stop()
        }

        Column {
            anchors.centerIn: parent
            width: Math.max(1, parent.width - Theme.spacingSm * 2)
            spacing: Theme.spacingXs
            visible: !captureView.visible

            AureliaIcon {
                id: previewIcon
                anchors.horizontalCenter: parent.horizontalCenter
                width: 24
                height: 24
                iconSize: 24
                name: ""
                sourcePath: root.iconSource
                preserveColors: !root.symbolicIcon
                tint: Theme.text
                opacity: 0.9
            }

            Text {
                width: parent.width
                text: root.windowTitle
                color: Theme.textSecondary
                font.family: Theme.fontFamilyResolved
                font.pixelSize: Theme.fontSizeXs
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 24
            color: Qt.rgba(Theme.bgBase.r, Theme.bgBase.g, Theme.bgBase.b, 0.78)

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingXs
                anchors.rightMargin: Theme.spacingXs
                spacing: Theme.spacingXs

                AureliaIcon {
                    id: windowIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    iconSize: 16
                    name: ""
                    sourcePath: root.iconSource
                    preserveColors: !root.symbolicIcon
                    tint: Theme.text
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, parent.width - 20)
                    text: root.windowTitle
                    color: Theme.text
                    font.family: Theme.fontFamilyResolved
                    font.pixelSize: Theme.fontSizeXs
                    elide: Text.ElideRight
                }
            }
        }
    }

    Timer {
        id: captureRetry
        interval: 90
        repeat: false
        onTriggered: root.requestFrame()
    }

    Component.onCompleted: {
        root.refreshIconResolution()
        root.requestFrame()
    }
}
