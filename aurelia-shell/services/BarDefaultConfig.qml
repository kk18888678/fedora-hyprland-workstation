import QtQuick
import Quickshell
import Quickshell.Io

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
                {id: "aurelia.clock", format: "MMM d, dddd HH:mm"},
                {id: "aurelia.weather", location: "auto"}
            ],
            right: [
                {id: "aurelia.tray"},
                {id: "aurelia.network"},
                {id: "aurelia.bluetooth"},
                {id: "aurelia.monitor"},
                {id: "aurelia.screenshot"},
                {id: "aurelia.power"}
            ]
        }
    })
    property var value: root.fallback
    property bool loaded: false

    function pathFromUrl(value) {
        var text = String(value || "")
        return text.indexOf("file://") === 0 ? decodeURIComponent(text.substring(7)) : text
    }

    function cloneJson(candidate) {
        try {
            return JSON.parse(JSON.stringify(candidate))
        } catch (error) {
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
        try {
            var parsed = JSON.parse(String(raw || ""))
            if (root.validDocument(parsed)) {
                root.value = root.cloneJson(parsed) || root.fallback
                root.loaded = true
                return
            }
        } catch (error) {}
        root.value = root.cloneJson(root.fallback)
        root.loaded = false
    }

    function copy() {
        return root.cloneJson(root.value) || root.cloneJson(root.fallback)
    }

    property FileView defaultFile: FileView {
        path: root.defaultPath
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: root.load(text())
        onLoadFailed: root.load("")
    }

    Component.onCompleted: root.defaultFile.reload()
}
