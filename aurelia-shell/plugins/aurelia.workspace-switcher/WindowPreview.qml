import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"

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
        var id = root.appId
        return id !== "" ? DesktopEntries.heuristicLookup(id) : null
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

    function iconSource() {
        var icon = root.appEntry && root.appEntry.icon ? String(root.appEntry.icon) : ""
        if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(icon)) icon = "application-x-executable"
        return Quickshell.iconPath(icon, "application-x-executable")
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

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 24
                height: 24
                source: root.iconSource()
                sourceSize: Qt.size(24, 24)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                opacity: 0.9
            }

            Text {
                width: parent.width
                text: root.windowTitle
                color: Theme.textSecondary
                font.family: Theme.fontFamily
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

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    source: root.iconSource()
                    sourceSize: Qt.size(16, 16)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, parent.width - 20)
                    text: root.windowTitle
                    color: Theme.text
                    font.family: Theme.fontFamily
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

    Component.onCompleted: root.requestFrame()
}
