import QtQuick
import Quickshell
import Quickshell.Io
import "AureliaAppSearch.js" as AppSearch

// Shared native application library for Aurelia command surfaces.
//
// Quickshell owns the XDG Desktop Entry model. This service owns only the
// normalized search projection and icon lookup; launch execution remains in
// the backend so terminal entries, UWSM, and Fedora fallbacks have one owner.
Item {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHomeOverride: Quickshell.env("XDG_CONFIG_HOME") || ""
    readonly property string configHome: configHomeOverride.charAt(0) === "/" ? configHomeOverride : (home + "/.config")
    readonly property string defaultHiddenPath: pathFromUrl(Qt.resolvedUrl("../config/command-center.hides"))
    readonly property string userHiddenPath: configHome + "/aurelia/command-center.hides"
    readonly property var builtinHiddenIds: ({
        "footclient": true,
        "foot-server": true
    })

    property var defaultHiddenIds: builtinHiddenIds
    property var userHiddenIds: ({})
    property var hiddenApplicationIds: builtinHiddenIds

    signal appsChanged()

    function pathFromUrl(value) {
        var text = String(value || "")
        return text.indexOf("file://") === 0 ? decodeURIComponent(text.substring(7)) : text
    }

    function normalizeDesktopId(value) {
        var id = String(value || "").trim()
        if (id === "" || id.charAt(0) === "#") return ""
        var comment = id.indexOf("#")
        if (comment >= 0) id = id.substring(0, comment).trim()
        if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
        return /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(id) ? id.toLowerCase() : ""
    }

    function parseHiddenEntries(rawText) {
        var result = {}
        var lines = String(rawText || "").split(/\r?\n/)
        for (var i = 0; i < lines.length; i++) {
            var id = root.normalizeDesktopId(lines[i])
            if (id !== "") result[id] = true
        }
        return result
    }

    function mergeHiddenIds() {
        var next = {}
        for (var builtin in root.builtinHiddenIds) next[builtin] = true
        for (var defaultId in root.defaultHiddenIds) next[defaultId] = true
        for (var userId in root.userHiddenIds) next[userId] = true
        root.hiddenApplicationIds = next
        root.appsChanged()
    }

    function loadDefaultHiddenEntries(rawText) {
        root.defaultHiddenIds = root.parseHiddenEntries(rawText)
        root.mergeHiddenIds()
    }

    function loadUserHiddenEntries(rawText) {
        root.userHiddenIds = root.parseHiddenEntries(rawText)
        root.mergeHiddenIds()
    }

    function isHiddenEntry(entry) {
        if (!entry) return true
        var id = root.normalizeDesktopId(entry.id)
        return entry.noDisplay === true || (id !== "" && root.hiddenApplicationIds[id] === true)
    }

    function entryName(entry) {
        return AppSearch.entryName(entry)
    }

    function entrySubtext(entry) {
        return AppSearch.entrySubtext(entry)
    }

    function desktopIdFor(entry) {
        var value = String(entry && entry.id || "")
        if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*(?:\.desktop)?$/.test(value)) return ""
        return value.slice(-8) === ".desktop" ? value : value + ".desktop"
    }

    function sortedEntries(query) {
        var values = DesktopEntries.applications.values || []
        return AppSearch.sortedEntries(values, query, function(entry) { return root.isHiddenEntry(entry) })
    }

    function iconSource(iconName) {
        var value = String(iconName || "")
        if (value === "") return Quickshell.iconPath("application-x-executable", "application-x-executable")
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
        if (value.charAt(0) === "/") return "file://" + value.split("/").map(encodeURIComponent).join("/")
        return Quickshell.iconPath(value, "application-x-executable")
    }

    function appRows(query) {
        var matches = root.sortedEntries(query || "")
        var rows = []
        var seen = {}
        for (var i = 0; i < matches.length; i++) {
            var entry = matches[i].entry
            var id = root.desktopIdFor(entry)
            if (id === "" || seen[id]) continue
            seen[id] = true
            rows.push({
                id: "app:" + id,
                kind: "app",
                moduleId: "apps",
                appId: id,
                label: root.entryName(entry),
                subtitle: root.entrySubtext(entry) || "Application",
                detail: "Applications",
                icon: "",
                appIcon: String(entry.icon || ""),
                sourceScore: matches[i].score,
                order: 20,
                keywords: AppSearch.entrySearchText(entry)
            })
        }
        return rows
    }

    property FileView defaultHiddenFile: FileView {
        path: root.defaultHiddenPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadDefaultHiddenEntries(text())
        onFileChanged: reload()
        onLoadFailed: root.loadDefaultHiddenEntries("")
    }

    property FileView userHiddenFile: FileView {
        path: root.userHiddenPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadUserHiddenEntries(text())
        onFileChanged: reload()
        onLoadFailed: root.loadUserHiddenEntries("")
    }

    Component.onCompleted: {
        root.defaultHiddenFile.reload()
        root.userHiddenFile.reload()
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.appsChanged() }
    }
}
