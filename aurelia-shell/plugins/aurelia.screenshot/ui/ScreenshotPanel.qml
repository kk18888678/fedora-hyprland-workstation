import QtQuick

// Controller for the screenshot bar widget. The menu is a bar-owned popup;
// the only fullscreen surface is the short-lived region drag overlay.
Item {
    id: panelRoot

    property string backendBin: ""
    property var bar: null
    property var anchorItem: null
    property bool menuOpen: false
    property string statusMessage: ""
    property string statusKind: "info"
    property string captureStage: "menu"
    property int delaySeconds: 0
    property bool showPointer: false
    property bool quickCapture: false
    property bool preserveSurfaceDuringCapture: false
    property bool menuSuppressed: false

    signal captureRequested(string mode, int delay, string geometry, bool pointer)

    function isVisible() {
        return menuOpen || captureStage === "region-selecting"
    }

    readonly property int popupHeight: 228

    function resetMenu() {
        menuSuppressed = false
        captureStage = "menu"
        statusMessage = ""
        statusKind = "info"
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
                var requestedMode = String(payload.mode)
                if (requestedMode === "screen") requestedMode = "full"
                if (requestedMode === "region" && String(payload.geometry || "") === "") startRegionSelection()
                else capture(requestedMode, requestedDelay, String(payload.geometry || ""))
            }
        } catch (error) {
            statusMessage = "Invalid screenshot request."
            statusKind = "error"
        }
    }

    function close() {
        hideMenuSurface()
        captureStage = "menu"
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
        var requestedMode = String(mode || "")
        if (requestedMode === "screen") requestedMode = "full"
        if (["full", "region", "smart"].indexOf(requestedMode) === -1) {
            statusMessage = "Unsupported screenshot mode."
            statusKind = "error"
            menuOpen = true
            return
        }
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
        captureRequested(requestedMode, safeDelay, String(geometry || ""), showPointer)
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
        statusMessage = "Select a region..."
        statusKind = "info"
        console.info("[SCREENSHOT] region selection overlay started")
        hideMenuSurface()
        menuOpen = false
    }

    function cancelRegionSelection() {
        console.info("[SCREENSHOT] region selection cancelled")
        quickCapture = false
        captureStage = "menu"
        menuOpen = false
        statusMessage = ""
        statusKind = "info"
    }

    function regionSelectionTooSmall() {
        console.info("[SCREENSHOT] region selection too small")
        statusMessage = "Selection is too small. Try again."
        statusKind = "error"
    }

    function regionSelectionFinished(geometry) {
        var selectedGeometry = String(geometry || "")
        if (selectedGeometry.length === 0) return
        capture("region", delaySeconds, selectedGeometry)
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

}
