import QtQuick
import Quickshell
import "AureliaAppSearch.js" as AppSearch

// Shared native application library for Aurelia command surfaces.
//
// Quickshell owns the XDG Desktop Entry model. This service owns only the
// normalized search projection and icon lookup; launch execution remains in
// the backend so terminal entries, UWSM, and Fedora fallbacks have one owner.
Item {
    id: root

    signal appsChanged()

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
        return AppSearch.sortedEntries(values, query, function(entry) {
            return entry && entry.noDisplay === true
        })
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

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.appsChanged() }
    }
}
