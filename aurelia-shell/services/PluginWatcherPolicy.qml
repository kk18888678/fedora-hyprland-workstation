import QtQuick

// Maps bounded inotify paths to discovered plugin IDs without assuming that a
// first-party plugin is always the first directory below the plugin root.
QtObject {
    id: policy

    property var registry: null
    readonly property var watchedExtensions: ["qml", "js", "json", "jsonc", "lua", "conf"]

    function rootForPath(filePath) {
        var path = String(filePath || "").trim()
        if (path.charAt(0) !== "/" || !policy.registry) return ""
        var roots = [policy.registry.firstPartyDir, policy.registry.userPluginsDir]
        for (var i = 0; i < roots.length; i++) {
            var root = String(roots[i] || "").replace(/\/$/, "")
            if (root !== "" && path.indexOf(root + "/") === 0) return root
        }
        return ""
    }

    function isWatchedPath(filePath) {
        var path = String(filePath || "").trim()
        var root = policy.rootForPath(path)
        if (root === "") return false
        var relative = path.substring(root.length + 1)
        if (!relative || relative.indexOf(".") === 0 || relative.indexOf("/.git/") !== -1 ||
            relative.endsWith("/.git")) return false
        for (var i = 0; i < policy.watchedExtensions.length; i++) {
            if (relative.endsWith("." + policy.watchedExtensions[i])) return true
        }
        return false
    }

    function pluginIdForPath(filePath) {
        var path = String(filePath || "").trim()
        var root = policy.rootForPath(path)
        if (root === "" || !policy.isWatchedPath(path)) return ""

        var ids = policy.registry ? Object.keys(policy.registry.installedPlugins).sort() : []
        var matched = ""
        var matchedLength = -1
        var matchedCount = 0
        for (var i = 0; i < ids.length; i++) {
            var manifest = policy.registry.installedPlugins[ids[i]]
            var source = String(manifest && manifest.__sourceDir || "").replace(/\/$/, "")
            if (source === "" || (path !== source && path.indexOf(source + "/") !== 0)) continue
            if (source.length > matchedLength) {
                matched = ids[i]
                matchedLength = source.length
                matchedCount = 1
            } else if (source.length === matchedLength) {
                matchedCount++
            }
        }
        if (matchedCount === 1 && matched !== "") return matched

        var relative = path.substring(root.length + 1)
        var slash = relative.indexOf("/")
        var candidate = slash === -1 ? relative : relative.substring(0, slash)
        if (policy.registry && policy.registry.isValidPluginId(candidate)) {
            if (root === policy.registry.userPluginsDir || candidate.indexOf("aurelia.") === 0) return candidate
        }
        return ""
    }
}
