import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "../ui"

// Resident core screenshot service.
//
// The screenshot capability is owned here, not by the `aurelia.screenshot`
// bar-widget plugin. This service owns the capture state machine, the single
// bounded capture Process over bin/aurelia-screenshot, the region-selection
// overlay, the menu popup, and the notification publish. The plugin widget is
// a thin bar affordance over this service, so disabling the plugin, removing
// the widget from the bar layout, or uninstalling the plugin can never
// unregister the SUPER+SHIFT+R/S shortcut or leave `shell call
// aurelia.screenshot` without a live handler.
Item {
    id: service

    // Injected by shell.qml. `shell` is the resident shell IPC surface used
    // for the notification publish; `pluginHost` provides the active bar for
    // popup anchoring only.
    property var shell: null
    property var pluginHost: null
    property string aureliaPath: ""
    // Constructor-injected only by isolated fixtures. Production always runs
    // the real bounded capture process.
    property bool testMode: false

    // Observability hook: emitted when a capture request is admitted. The
    // fixture uses the recorded state rather than connecting to it.
    signal captureStarted(string mode, int delay, string geometry, bool pointer)

    readonly property var bar: pluginHost ? pluginHost.activeBar() : null
    // The popup anchors to the widget slot when one is mounted and falls back
    // to the bar content anchor when the widget is disabled or removed.
    readonly property var barAnchorItem: bar && typeof bar.barAnchorItem === "function"
        ? bar.barAnchorItem() : null

    implicitWidth: 0
    implicitHeight: 0

    property double captureStartedAt: 0
    property bool capturePending: false
    property var pendingCaptureRequest: null
    property int captureCount: 0
    property var lastCaptureRequest: ({ mode: "", delay: -1, geometry: "", pointer: false })
    property string lastDiagnostic: ""

    readonly property var controller: panel

    readonly property string backendBin: aureliaPath !== ""
        ? aureliaPath + "/bin/aurelia-screenshot"
        : "/usr/local/bin/aurelia-screenshot"
    readonly property var processEnvironment: {
        return {
            "PATH": "/usr/local/bin:/usr/bin:/bin" + (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : ""),
            "HOME": Quickshell.env("HOME") || "",
            "WAYLAND_DISPLAY": Quickshell.env("WAYLAND_DISPLAY") || "",
            "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || "",
            "DISPLAY": Quickshell.env("DISPLAY") || "",
            "HYPRLAND_INSTANCE_SIGNATURE": Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "",
            "XDG_PICTURES_DIR": Quickshell.env("XDG_PICTURES_DIR") || ""
        }
    }

    ScreenshotPanel {
        id: panel

        bar: service.bar
        anchorItem: service.barAnchorItem
        backendBin: service.backendBin
    }

    // The menu popup is a layer-shell surface. Loading it by URL behind a
    // Loader keeps a missing compositor backend from taking down the whole
    // service: quick capture still works, and the failure is recorded instead
    // of wedging the shell.
    Loader {
        id: menuLoader
        active: true
        source: Qt.resolvedUrl("../ui/ScreenshotMenuPopup.qml")

        readonly property bool menuVisible: item ? item.visible === true : false

        onLoaded: if (item) item.controller = panel
        onStatusChanged: {
            if (status === Loader.Error) {
                service.lastDiagnostic = "Screenshot menu surface unavailable."
                console.error("[SCREENSHOT] menu_load_failed")
            }
        }
    }

    Loader {
        id: selectionLoader
        active: panel.captureStage === "region-selecting"
        source: Qt.resolvedUrl("../ui/ScreenshotSelectionOverlay.qml")

        onLoaded: if (item) item.controller = panel
        onStatusChanged: {
            if (status === Loader.Error) {
                service.lastDiagnostic = "Region selection overlay failed to load."
                console.error("[SCREENSHOT] overlay_load_failed")
                // Never leave the user trapped in a selection stage with no
                // surface to interact with. Defer so this status callback
                // cannot re-enter the Loader's own active binding.
                Qt.callLater(function() { panel.cancelRegionSelection() })
            }
        }
    }

    function open(payloadJson) {
        panel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        cancelCapture()
        panel.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (isVisible()) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return panel.isVisible()
    }

    function quickRegion() {
        panel.quickRegion()
        return "started"
    }

    function quickScreen() {
        panel.quickScreen()
        return "started"
    }

    function capture(payloadJson) {
        panel.capturePayload(payloadJson || "{}")
        return "started"
    }

    // One in-process entry point shared by the direct `aurelia.screenshot` IPC
    // target and the core-aware `shell call` fallback.
    function ipcCall(method, argument) {
        var requested = String(method || "")
        var payload = argument === undefined || argument === null || argument === "" ? "{}" : String(argument)
        if (requested === "ping") return "ok"
        if (requested === "open") return open(payload)
        if (requested === "close") return close()
        if (requested === "toggle") return toggle(payload)
        if (requested === "isVisible") return isVisible() ? "true" : "false"
        if (requested === "quickRegion") return quickRegion()
        if (requested === "quickScreen") return quickScreen()
        if (requested === "capture") return capture(payload)
        return "invalid-method"
    }

    // Deterministic drain for reload/teardown. The resident service is not a
    // plugin reload boundary, but an explicit cancel keeps a capture from
    // outliving its owner if the shell is restarted.
    function cancelCapture() {
        capturePending = false
        pendingCaptureRequest = null
        if (captureProcess.running) captureProcess.running = false
    }

    function startPendingCapture() {
        if (!pendingCaptureRequest) return
        // The menu is a separate layer-shell window. Freeze the frame only
        // after it has actually disappeared so the popup is never captured.
        if (menuLoader.menuVisible) return
        var request = pendingCaptureRequest
        pendingCaptureRequest = null
        capturePending = false
        lastCaptureRequest = {
            mode: String(request.mode || ""),
            delay: Number(request.delay) || 0,
            geometry: String(request.geometry || ""),
            pointer: request.pointer === true
        }
        captureCount++
        captureStarted(lastCaptureRequest.mode, lastCaptureRequest.delay,
            lastCaptureRequest.geometry, lastCaptureRequest.pointer)
        if (testMode) {
            console.info("[SCREENSHOT] capture.fixture mode=" + lastCaptureRequest.mode)
            panel.captureCompleted(0, (aureliaPath || "/tmp") + "/screenshot-fixture.png", "", 0)
            return
        }
        if (backendBin === "" || backendBin.charAt(0) !== "/") {
            service.lastDiagnostic = "Screenshot backend is unavailable."
            console.error("[SCREENSHOT] backend_unavailable path=" + backendBin)
            panel.captureCompleted(1, "", service.lastDiagnostic, 0)
            return
        }
        var command = [backendBin, "capture", lastCaptureRequest.mode,
            "--delay", String(lastCaptureRequest.delay)]
        command.push(lastCaptureRequest.pointer ? "--show-pointer" : "--hide-pointer")
        if (lastCaptureRequest.geometry && lastCaptureRequest.geometry.length > 0)
            command.push("--geometry", lastCaptureRequest.geometry)
        captureStartedAt = Date.now()
        console.info("[SCREENSHOT] capture.begin mode=" + lastCaptureRequest.mode +
            " delay=" + lastCaptureRequest.delay +
            " geometry=" + lastCaptureRequest.geometry +
            " pointer=" + lastCaptureRequest.pointer)
        captureProcess.command = command
        captureProcess.running = true
    }

    function publishCapture(path) {
        if (!shell || typeof shell.call !== "function") {
            lastDiagnostic = "Notification preview unavailable."
            console.warn("[SCREENSHOT] notification_unavailable result=shell-api-missing")
            return
        }
        var result = String(shell.call("aurelia.notifications", "publishScreenshot",
            String(path || "")) || "")
        if (result !== "ok") {
            // A disabled notification plugin, an absent wl-copy, or an
            // unwritable save path must never disable the shortcut or block
            // activation. It must, however, remain observable.
            lastDiagnostic = "Screenshot saved; preview not published (" + result + ")."
            console.warn("[SCREENSHOT] notification_publish result=" + result)
        } else {
            console.info("[SCREENSHOT] notification.publish result=ok")
        }
    }

    Connections {
        target: panel

        function onCaptureRequested(mode, delay, geometry, pointer) {
            if (captureProcess.running || service.capturePending) return
            service.capturePending = true
            service.pendingCaptureRequest = {
                mode: mode,
                delay: delay,
                geometry: geometry,
                pointer: pointer
            }
            Qt.callLater(function() { service.startPendingCapture() })
        }
    }

    Connections {
        target: menuLoader.item
        function onVisibleChanged() { service.startPendingCapture() }
    }

    Process {
        id: captureProcess
        command: []
        environment: service.processEnvironment
        stdout: StdioCollector {
            id: captureStdout
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: captureStderr
            waitForEnd: true
        }

        onExited: function(code) {
            var duration = captureStartedAt > 0 ? (Date.now() - captureStartedAt) : 0
            var capturePath = captureStdout.text.trim()
            var errorText = captureStderr.text.trim()
            if (code === 0 && capturePath !== "") {
                console.info("[SCREENSHOT] capture.end code=" + code +
                    " duration_ms=" + duration + " path=" + capturePath)
                service.publishCapture(capturePath)
            } else {
                service.lastDiagnostic = errorText !== ""
                    ? errorText
                    : ("Capture failed (status " + code + ").")
                console.error("[SCREENSHOT] capture.end code=" + code +
                    " duration_ms=" + duration + " diagnostic=" + service.lastDiagnostic)
            }
            panel.captureCompleted(code, capturePath, errorText, duration)
        }
    }

    // Core-owned IPC target. The capability is reachable by target name
    // independently of the plugin host.
    IpcHandler {
        target: "aurelia.screenshot"

        function ping(): string { return service.ipcCall("ping", "") }
        function open(payloadJson: string): string { return service.ipcCall("open", payloadJson) }
        function close(): string { return service.ipcCall("close", "") }
        function toggle(payloadJson: string): string { return service.ipcCall("toggle", payloadJson) }
        function isVisible(): string { return service.ipcCall("isVisible", "") }
        function quickRegion(): string { return service.ipcCall("quickRegion", "") }
        function quickScreen(): string { return service.ipcCall("quickScreen", "") }
        function capture(payloadJson: string): string { return service.ipcCall("capture", payloadJson) }
    }

    Component.onDestruction: {
        if (captureProcess.running) captureProcess.running = false
    }
}
