import QtQuick

// Core-aware shell IPC routing.
//
// The screenshot capability is owned by the resident core ScreenshotService.
// `shell call aurelia.screenshot <method>` must keep resolving for existing
// scripts, the shipped `command_argv`, and user-modified binding strings, so
// this router prefers the core service for the screenshot target and only
// consults the plugin host as a compatibility fallback. An unresolved
// screenshot invocation becomes an explicit diagnostic marker rather than the
// ambiguous plugin "not-loaded" value, so the bounded IPC client can fail
// visibly instead of exiting 0 with no signal.
QtObject {
    id: router

    property var screenshotService: null
    property string screenshotTarget: "aurelia.screenshot"

    function call(pluginHost, pluginId, method, argument) {
        var target = String(pluginId || "")
        var requested = String(method || "")
        var payload = argument === undefined || argument === null ? "" : String(argument)

        if (target === router.screenshotTarget) {
            var core = router.screenshotService
            if (core && typeof core.ipcCall === "function") {
                try {
                    var coreResult = String(core.ipcCall(requested, payload) || "")
                    if (coreResult !== "" && coreResult !== "not-loaded") return coreResult
                } catch (error) {
                    console.error("[SCREENSHOT] core_call_failed method=" + requested +
                        " detail=" + String(error))
                }
            } else {
                console.error("[SCREENSHOT] core_service_missing method=" + requested)
            }
        }

        var result = pluginHost && typeof pluginHost.call === "function"
            ? pluginHost.call(pluginId, method, argument) : "not-loaded"
        if (target === router.screenshotTarget && (result === "not-loaded" || result === "error")) {
            console.error("[SCREENSHOT] unresolved method=" + requested + " result=" + String(result))
            return "screenshot-unavailable"
        }
        return result
    }
}
