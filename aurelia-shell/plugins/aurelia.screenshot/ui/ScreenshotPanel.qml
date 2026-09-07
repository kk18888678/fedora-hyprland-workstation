import QtQuick
import Quickshell
import Quickshell.Io

// Controller for the screenshot bar widget. The menu is a bar-owned popup;
// the only fullscreen surface is the short-lived region drag overlay.
Item {
    id: panelRoot

    property string backendBin: ""
    property var processEnvironment: ({})
    property var bar: null
    property var anchorItem: null
    property bool menuOpen: false
    property string statusMessage: ""
    property string statusKind: "info"
    property string captureStage: "menu"
    property string pendingGeometry: ""
    property string pendingWindowLabel: ""
    property int delaySeconds: 3
    property bool showPointer: false
    property bool quickCapture: false
    property bool preserveSurfaceDuringCapture: false
    property var windows: []
    property bool menuSuppressed: false

    signal captureRequested(string mode, int delay, string geometry, bool pointer)

    function isVisible() {
        return menuOpen || captureStage === "region-selecting"
    }

    function popupHeight() {
        if (captureStage === "window-list") return 560
        if (captureStage === "region-ready") return 470
        return 430
    }

    function resetMenu() {
        menuSuppressed = false
        captureStage = "menu"
        pendingGeometry = ""
        pendingWindowLabel = ""
        windows = []
        statusMessage = ""
        statusKind = "info"
        delaySeconds = 3
        showPointer = false
        quickCapture = false
        preserveSurfaceDuringCapture = false
    }

    function open(payloadJson) {
        resetMenu()
        menuOpen = true
        try {
            var payload = JSON.parse(payloadJson || "{}")
            if (payload.mode && payload.mode !== "menu") {
                var requestedDelay = payload.delay === undefined ? delaySeconds : Number(payload.delay)
                capture(String(payload.mode), requestedDelay, String(payload.geometry || ""))
            }
        } catch (error) {
            statusMessage = "Invalid screenshot request."
            statusKind = "error"
        }
    }

    function close() {
        if (windowsProcess.running) windowsProcess.running = false
        hideMenuSurface()
        captureStage = "menu"
        pendingGeometry = ""
        pendingWindowLabel = ""
        quickCapture = false
        preserveSurfaceDuringCapture = false
        menuOpen = false
    }

    function closeForPopoutSwitch() { close() }

    function hideMenuSurface() {
        menuSuppressed = true
        console.info("[SCREENSHOT] menu_surface_hidden")
    }

    function capture(mode, delay, geometry, preserveSurface) {
        var safeDelay = Number(delay)
        if (!Number.isFinite(safeDelay)) safeDelay = 0
        safeDelay = Math.max(0, Math.min(30, Math.floor(safeDelay)))
        statusMessage = safeDelay > 0 ? "Waiting " + safeDelay + " seconds..." : "Capturing..."
        statusKind = "info"
        captureStage = "capturing"
        preserveSurfaceDuringCapture = preserveSurface === true
        if (!preserveSurfaceDuringCapture) {
            hideMenuSurface()
            menuOpen = false
        }
        captureRequested(String(mode || "smart"), safeDelay, String(geometry || ""), showPointer)
    }

    function quickRegion() {
        resetMenu()
        quickCapture = true
        // The quick path deliberately goes straight to the native smart
        // picker. It does not open a competing Aurelia surface, so an
        // existing application menu remains the thing being captured.
        capture("smart", 0, "", true)
    }

    function capturePayload(payloadJson) { open(payloadJson) }

    function startRegionSelection() {
        if (!backendBin || backendBin.length === 0) {
            statusMessage = "Screenshot backend is unavailable."
            statusKind = "error"
            menuOpen = true
            return
        }
        captureStage = "region-selecting"
        pendingGeometry = ""
        statusMessage = "Select a region..."
        statusKind = "info"
        console.info("[SCREENSHOT] region selection overlay started")
        hideMenuSurface()
        menuOpen = false
    }

    function cancelRegionSelection() {
        console.info("[SCREENSHOT] region selection cancelled")
        quickCapture = false
        pendingGeometry = ""
        captureStage = "menu"
        menuOpen = false
        statusMessage = ""
        statusKind = "info"
    }

    function regionSelectionTooSmall() {
        console.warn("[SCREENSHOT] region selection too small")
    }

    function regionSelectionFinished(geometry) {
        pendingGeometry = String(geometry || "")
        if (pendingGeometry.length === 0) return
        if (quickCapture) {
            quickCapture = false
            capture("region", 0, pendingGeometry)
            return
        }
        captureStage = "region-ready"
        statusMessage = "Region selected. Capture it now or choose a delay."
        statusKind = "success"
        menuSuppressed = false
        menuOpen = true
    }

    function startWindowSelection() {
        if (windowsProcess.running || !backendBin || backendBin.length === 0) return
        captureStage = "window-list"
        statusMessage = "Loading open windows..."
        statusKind = "info"
        windows = []
        windowsProcess.command = [backendBin, "windows"]
        windowsProcess.running = true
    }

    function captureWindow(windowData) {
        var at = windowData.at || [0, 0]
        var size = windowData.size || [0, 0]
        if (at.length < 2 || size.length < 2 || Number(size[0]) <= 0 || Number(size[1]) <= 0) {
            statusMessage = "The selected window has no capturable geometry."
            statusKind = "error"
            return
        }
        pendingWindowLabel = windowData.title || windowData.class || "Window"
        var geometry = String(at[0]) + "," + String(at[1]) + " " + String(size[0]) + "x" + String(size[1])
        capture("window", delaySeconds, geometry)
    }

    function capturePendingRegion(delay) {
        if (!pendingGeometry) return
        capture("region", delay, pendingGeometry)
    }

    function captureCompleted(code, output, errorOutput, durationMs) {
        var wasQuick = quickCapture
        quickCapture = false
        captureStage = "menu"
        var result = String(output || "").trim()
        var errorText = String(errorOutput || "").trim()

        if (wasQuick) {
            // A cancelled quick picker must leave the application below it
            // untouched and must not reopen an Aurelia menu.
            if (!preserveSurfaceDuringCapture) menuOpen = false
            preserveSurfaceDuringCapture = false
            statusMessage = ""
            statusKind = "info"
            return
        }

        if (code === 0) {
            if (!preserveSurfaceDuringCapture) menuOpen = false
            preserveSurfaceDuringCapture = false
            statusMessage = result !== ""
                ? ("Screenshot saved and copied (" + durationMs + " ms).")
                : ("Screenshot captured (" + durationMs + " ms).")
            statusKind = "success"
        } else {
            preserveSurfaceDuringCapture = false
            menuSuppressed = false
            menuOpen = true
            statusMessage = errorText || ("Capture failed (status " + code + ").")
            statusKind = "error"
        }
    }

    Process {
        id: windowsProcess
        command: []
        environment: panelRoot.processEnvironment
        stdout: StdioCollector { id: windowsStdout }
        stderr: StdioCollector { id: windowsStderr }

        onExited: function(code) {
            if (code === 0) {
                try {
                    windows = JSON.parse(windowsStdout.text || "[]")
                    statusMessage = windows.length > 0 ? "Select an open window." : "No open windows found."
                    statusKind = "info"
                } catch (error) {
                    windows = []
                    captureStage = "menu"
                    statusMessage = "Could not read open windows."
                    statusKind = "error"
                }
            } else {
                captureStage = "menu"
                statusMessage = windowsStderr.text.trim() || "Could not query open windows."
                statusKind = "error"
            }
        }
    }

}
