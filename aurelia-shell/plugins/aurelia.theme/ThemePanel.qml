import QtQuick

// Compatibility wrapper for callers that still summon aurelia.theme. The
// resident image-picker owns the visual selector; this legacy panel remains a
// tiny routing boundary so there is only one theme-selection UI.
Item {
    id: root

    property string aureliaPath: ""
    property var shell: null
    property var manifest: ({})
    property var pluginRegistry: null

    function open(payloadJson) {
        var payload = { mode: "theme" }
        try {
            var requested = JSON.parse(String(payloadJson || "{}"))
            if (requested && requested.mode === "background") payload.mode = "background"
        } catch (error) {}

        if (!root.shell || typeof root.shell.summon !== "function") return "not-ready"
        root.shell.summon("aurelia.image-picker", JSON.stringify(payload))
        return "ok"
    }

    function close() { return "closed" }
    function isVisible() { return false }
}
