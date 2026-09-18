import QtQuick
import Quickshell
import Quickshell.Io
import "SourceUrl.js" as SourceUrl

// One repository-owned default bar document with a small in-memory recovery
// fallback. Runtime user state still wins; this object only supplies defaults.
QtObject {
    id: root

    readonly property string defaultPath: root.pathFromUrl(Qt.resolvedUrl("../config/bar-default.json"))
    readonly property var fallback: ({
        id: "aurelia.bar",
        position: "top",
        transparent: false,
        centerAnchor: "aurelia.clock",
        layout: {
            left: [{id: "aurelia.workspaces"}],
            center: [
                {id: "aurelia.notifications"},
                {id: "aurelia.clock", format: "auto"},
                {id: "aurelia.weather", location: "auto"}
            ],
            right: [
                {id: "aurelia.tray"},
                {id: "aurelia.network"},
                {id: "aurelia.audio"},
                {id: "aurelia.bluetooth"},
                {id: "aurelia.monitor"},
                {id: "aurelia.screenshot"},
                {id: "aurelia.session-actions"},
                {id: "aurelia.power"}
            ]
        }
    })
    property var value: root.fallback
    property bool loaded: false
    property string lastError: ""

    function pathFromUrl(value) {
        return SourceUrl.pathFromUrl(value)
    }

    function cloneJson(candidate) {
        try {
            return JSON.parse(JSON.stringify(candidate))
        } catch (error) {
            root.lastError = "Bar default configuration could not be cloned."
            console.error("[BAR] default_config_clone_failed")
            return null
        }
    }

    function validEntry(entry) {
        return entry && typeof entry === "object" && !Array.isArray(entry) &&
            typeof entry.id === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(entry.id) &&
            entry.id.indexOf("..") === -1
    }

    function validDocument(candidate) {
        if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) return false
        if (typeof candidate.id !== "string" || candidate.id !== "aurelia.bar") return false
        if (["top", "bottom", "left", "right"].indexOf(candidate.position) === -1) return false
        if (typeof candidate.transparent !== "boolean" || typeof candidate.centerAnchor !== "string") return false
        if (!candidate.layout || typeof candidate.layout !== "object" || Array.isArray(candidate.layout)) return false
        var sections = ["left", "center", "right"]
        for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
            var section = sections[sectionIndex]
            if (!Array.isArray(candidate.layout[section])) return false
            for (var i = 0; i < candidate.layout[section].length; i++)
                if (!root.validEntry(candidate.layout[section][i])) return false
        }
        return true
    }

    function load(raw) {
        root.lastError = ""
        var parsed = null
        try {
            parsed = JSON.parse(String(raw || ""))
        } catch (error) {
            root.lastError = "Bar default configuration is not valid JSON."
            console.error("[BAR] default_config_load_failed reason=invalid_json")
        }
        if (root.validDocument(parsed)) {
            root.value = root.cloneJson(parsed) || root.fallback
            root.loaded = true
            return
        }
        if (root.lastError === "") {
            root.lastError = "Bar default configuration has an invalid shape."
            console.error("[BAR] default_config_load_failed reason=invalid_shape")
        }
        root.value = root.cloneJson(root.fallback)
        root.loaded = false
    }

    function copy() {
        return root.cloneJson(root.value) || root.cloneJson(root.fallback)
    }

    property FileView defaultFile: FileView {
        path: root.defaultPath
        watchChanges: true
        printErrors: true
        onLoaded: root.load(text())
        onFileChanged: root.load(text())
        onLoadFailed: root.load("")
    }

    Component.onCompleted: root.defaultFile.reload()
}
