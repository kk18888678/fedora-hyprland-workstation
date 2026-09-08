import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../../theme"
import "../../../ui"

// Screenshot is a first-class bar widget. It owns the controller, capture
// process, and keyboard panel directly, matching the lifecycle used by the
// Weather and Power bar widgets.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string aureliaPath: ""
    property string moduleName: "aurelia.screenshot"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
    property double captureStartedAt: 0
    property bool capturePending: false
    property var pendingCaptureRequest: null

    readonly property var screenshotPanel: panelLoader.item

    readonly property string backendBin: aureliaPath !== ""
        ? aureliaPath + "/bin/aurelia-screenshot"
        : "/usr/local/bin/aurelia-screenshot"
    readonly property var processEnvironment: {
        var env = {
            "PATH": "/usr/local/bin:/usr/bin:/bin" + (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : ""),
            "HOME": Quickshell.env("HOME") || "",
            "WAYLAND_DISPLAY": Quickshell.env("WAYLAND_DISPLAY") || "",
            "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || "",
            "DISPLAY": Quickshell.env("DISPLAY") || "",
            "HYPRLAND_INSTANCE_SIGNATURE": Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "",
            "XDG_PICTURES_DIR": Quickshell.env("XDG_PICTURES_DIR") || ""
        }
        return env
    }

    implicitWidth: bar ? bar.barSize : 38
    implicitHeight: bar ? bar.barSize : 38

    function configurePanel(target) {
        if (!target) return
        if ("backendBin" in target) target.backendBin = root.backendBin
        if ("bar" in target) target.bar = root.bar
        if ("anchorItem" in target) target.anchorItem = root.barAnchorItem || root
    }

    function open(payloadJson) {
        screenshotPanel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        capturePending = false
        pendingCaptureRequest = null
        if (captureProcess.running) captureProcess.running = false
        screenshotPanel.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (isVisible()) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return screenshotPanel.isVisible()
    }

    function quickRegion() {
        screenshotPanel.quickRegion()
        return "started"
    }

    function quickScreen() {
        screenshotPanel.quickScreen()
        return "started"
    }

    function capture(payloadJson) {
        screenshotPanel.capturePayload(payloadJson || "{}")
        return "started"
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("ScreenshotPanel.qml")
        onLoaded: root.configurePanel(item)
        onStatusChanged: {
            if (status === Loader.Error) console.error("[SCREENSHOT] panel_load_failed")
        }
    }

    Component {
        id: menuComponent
        ScreenshotMenuPopup { controller: root.screenshotPanel }
    }

    Loader {
        id: menuLoader
        active: true
        sourceComponent: menuComponent
    }

    Component {
        id: selectionComponent
        ScreenshotSelectionOverlay { controller: root.screenshotPanel }
    }

    Loader {
        id: selectionLoader
        active: root.screenshotPanel && root.screenshotPanel.captureStage === "region-selecting"
        sourceComponent: selectionComponent
    }

    onAureliaPathChanged: root.configurePanel(panelLoader.item)
    onBarChanged: root.configurePanel(panelLoader.item)
    onBarAnchorItemChanged: root.configurePanel(panelLoader.item)

    function startPendingCapture() {
        if (!root.pendingCaptureRequest) return
        var menu = menuLoader.item
        // ScreenshotPanel has already requested closure. Wait for the actual
        // layer-shell backing surface to disappear before freezing the frame.
        if (menu && (menu.visible || menu.backingWindowVisible)) return
        var request = root.pendingCaptureRequest
        root.pendingCaptureRequest = null
        root.capturePending = false
        var command = [root.backendBin, "capture", request.mode, "--delay", String(request.delay)]
        command.push(request.pointer ? "--show-pointer" : "--hide-pointer")
        if (request.geometry && request.geometry.length > 0) command.push("--geometry", request.geometry)
        root.captureStartedAt = Date.now()
        console.info("[SCREENSHOT] capture.begin mode=" + request.mode + " delay=" + request.delay + " geometry=" + request.geometry + " pointer=" + request.pointer)
        captureProcess.command = command
        captureProcess.running = true
    }

    Process {
        id: captureProcess
        command: []
        environment: root.processEnvironment
        stdout: StdioCollector { id: captureStdout }
        stderr: StdioCollector { id: captureStderr }

        onExited: function(code) {
            var duration = captureStartedAt > 0 ? (Date.now() - captureStartedAt) : 0
            console.info("[SCREENSHOT] capture.end code=" + code + " duration_ms=" + duration + " path=" + captureStdout.text.trim() + " error=" + captureStderr.text.trim())
            screenshotPanel.captureCompleted(code, captureStdout.text, captureStderr.text, duration)
        }
    }

    Connections {
        target: panelLoader.item

        function onCaptureRequested(mode, delay, geometry, pointer) {
            if (captureProcess.running || root.capturePending) return
            root.capturePending = true
            root.pendingCaptureRequest = {
                mode: mode,
                delay: delay,
                geometry: geometry,
                pointer: pointer
            }
            Qt.callLater(function() {
                root.startPendingCapture()
            })
        }
    }

    Connections {
        target: menuLoader.item
        function onVisibleChanged() { root.startPendingCapture() }
        function onBackingWindowVisibleChanged() { root.startPendingCapture() }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: hover.hovered ? Theme.selection : "transparent"

        HoverHandler { id: hover }

        AureliaIcon {
            anchors.centerIn: parent
            width: 18
            height: 18
            name: "camera-photo"
            iconSize: 18
            tint: hover.hovered ? Theme.text : Theme.accent
        }

        AureliaToolTip {
            id: screenshotToolTip
            triggerItem: root
            bar: root.bar
            hovered: hover.hovered
            text: "Screenshots · Full Screen or Selection"
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.open("{\"mode\":\"menu\"}")
            }
        }
    }
}
