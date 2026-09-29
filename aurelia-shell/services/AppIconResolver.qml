pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "AppIconResolver.js" as Logic
import "SourceUrl.js" as SourceUrl

// Shared application-icon owner for Aurelia.
//
// This singleton is the single source of truth for "given a notification or
// window identity, which icon source should be rendered, and may it be tinted
// as a symbolic mask?". All ordering, normalisation and validation lives in
// the pure companion AppIconResolver.js so it stays node-testable; this file
// supplies only the environment probes (theme lookup through Qt, file
// existence, direct .desktop/AppStream reads and /proc identity) and never
// invents its own ordering.
//
// Surfaces must consume `resolve(...)` rather than re-deriving "file:// /
// image:// / absolute means as-is, else Quickshell.iconPath". In particular
// the symbolic-vs-full-colour rule lives here so no widget re-implements it.
QtObject {
    id: resolverRoot

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string xdgDataHome: {
        var value = Quickshell.env("XDG_DATA_HOME") || ""
        return value.charAt(0) === "/" ? value : resolverRoot.home + "/.local/share"
    }
    readonly property var xdgDataDirs: {
        var raw = Quickshell.env("XDG_DATA_DIRS") || ""
        if (raw === "") raw = "/usr/local/share:/usr/share"
        return String(raw).split(":")
    }

    // One reusable blocking FileView. `text()` and `data()` read the file
    // synchronously after `path` is assigned, so resolution needs no event
    // loop turn and no subprocess. Error reporting stays enabled per the
    // repository diagnostic-visibility policy; a read result is cached so each
    // unique candidate path is probed at most once per shell generation.
    property var textCache: ({"": ""})
    property var dataCache: ({})
    property FileView reader: FileView {
        blockLoading: true
        blockAllReads: true
        printErrors: true
    }

    // Direct .desktop/AppStream metadata is read from a bounded index of the
    // existing metadata files, built once with an argv-array find. Reading a
    // known-present file through the FileView keeps the optional-file probes
    // free of expected "file does not exist" warnings while still resolving
    // directly (never through Quickshell's asynchronous desktop-entry scan).
    property var knownMetadataFiles: ({})
    property string metadataIndexErrors: ""
    property int metadataIndexRevision: 0
    property Process metadataIndex: Process {
        stdout: StdioCollector { id: metadataIndexOut; waitForEnd: true }
        stderr: StdioCollector { id: metadataIndexErr; waitForEnd: true }
        onExited: {
            var lines = String(metadataIndexOut.text || "").split("\n")
            var next = {}
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].replace(/\s+$/, "")
                if (line.charAt(0) === "/") next[line] = true
            }
            resolverRoot.knownMetadataFiles = next
            resolverRoot.metadataIndexErrors = String(metadataIndexErr.text || "")
            resolverRoot.metadataIndexRevision = resolverRoot.metadataIndexRevision + 1
        }
    }
    Component.onCompleted: resolverRoot.rebuildMetadataIndex()

    function rebuildMetadataIndex() {
        var roots = resolverRoot.applicationsDirs().concat(resolverRoot.metainfoDirs())
        var argv = ["/usr/bin/find"]
        for (var i = 0; i < roots.length; i++) argv.push(roots[i])
        argv.push("-maxdepth", "1", "-type", "f", "(",
            "-name", "*.desktop", "-o", "-name", "*.metainfo.xml", "-o", "-name", "*.appdata.xml", ")")
        resolverRoot.metadataIndex.command = argv
        resolverRoot.metadataIndex.running = true
    }

    function metadataFileExists(path) {
        return resolverRoot.knownMetadataFiles[path] === true
    }

    // ------------------------------------------------------------------
    // Host probes
    // ------------------------------------------------------------------

    function readText(path) {
        var value = Logic.cleanField(path, Logic.MAX_PATH)
        if (value === "" || value.charAt(0) !== "/") return ""
        if (resolverRoot.textCache[value] !== undefined) return resolverRoot.textCache[value]
        resolverRoot.reader.path = value
        var content = resolverRoot.reader.text()
        var result = content === null || content === undefined ? "" : String(content)
        resolverRoot.textCache[value] = result
        return result
    }

    function fileUsable(path) {
        var value = Logic.cleanField(path, Logic.MAX_PATH)
        if (value === "" || value.charAt(0) !== "/") return false
        if (resolverRoot.dataCache[value] !== undefined) return resolverRoot.dataCache[value]
        resolverRoot.reader.path = value
        var data = resolverRoot.reader.data()
        var usable = data !== null && data !== undefined &&
            data.byteLength !== undefined && data.byteLength > 0
        resolverRoot.dataCache[value] = usable
        return usable
    }

    // File-URL construction is delegated to the approved SourceUrl owner so
    // the resolver never grows its own ad-hoc file:// concatenation.
    function fileSource(path) {
        return SourceUrl.fileUrl(path)
    }

    // Theme lookup is delegated to Qt: Quickshell implements the freedesktop
    // Icon Theme Specification (XDG icon dirs, ~/.icons, pixmaps, inheritance
    // and scale directories). The resolver never walks icon directories.
    function themeUsable(name) {
        var lookup = Logic.themeLookupName(name)
        if (lookup === "") return false
        return Quickshell.hasThemeIcon(lookup) === true
    }

    function themeSource(name) {
        var lookup = Logic.themeLookupName(name)
        if (lookup === "") lookup = Logic.DEFAULT_ICON
        return Quickshell.iconPath(lookup, Logic.DEFAULT_ICON)
    }

    function inlineUsable(source) {
        return Logic.cleanField(source, Logic.MAX_PATH) !== ""
    }

    property var probe: ({
        fileUsable: function(path) { return resolverRoot.fileUsable(path) },
        fileSource: function(path) { return resolverRoot.fileSource(path) },
        themeUsable: function(name) { return resolverRoot.themeUsable(name) },
        themeSource: function(name) { return resolverRoot.themeSource(name) },
        inlineUsable: function(source) { return resolverRoot.inlineUsable(source) }
    })

    // ------------------------------------------------------------------
    // Public helper surface
    // ------------------------------------------------------------------

    // The canonical theme lookup name for a possibly query-carrying value.
    function themeLookupName(value) {
        return Logic.themeLookupName(value)
    }

    // True when a name is a symbolic mask and must be tinted.
    function isSymbolicName(value) {
        return Logic.isSymbolicName(value)
    }

    // {name, symbolic} for callers that hold a name rather than a resolved
    // result (for example a test seam or a raw desktop icon).
    function describeName(value) {
        return {
            name: Logic.themeLookupName(value),
            symbolic: Logic.isSymbolicName(value)
        }
    }

    // ------------------------------------------------------------------
    // Resolution
    // ------------------------------------------------------------------

    // resolve({localPath, imageData, appIcon, image, desktopEntry, appName,
    //         origin}) -> {source, name, symbolic, kind, origin}
    function resolve(input) {
        var source = input || {}
        var cleanInput = {
            localPath: Logic.cleanField(source.localPath, Logic.MAX_PATH),
            imageData: Logic.cleanField(source.imageData, Logic.MAX_PATH),
            appIcon: Logic.cleanField(source.appIcon, Logic.MAX_PATH),
            image: Logic.cleanField(source.image, Logic.MAX_PATH),
            desktopEntry: Logic.cleanField(source.desktopEntry, Logic.MAX_ID),
            appName: Logic.cleanField(source.appName, Logic.MAX_FIELD),
            origin: resolverRoot.sanitizeOrigin(source.origin)
        }
        var metadata = resolverRoot.collectMetadata(cleanInput)
        return Logic.resolve(cleanInput, metadata, resolverRoot.probe)
    }

    // The in-flight origin record is consumed, never recreated. Unknown fields
    // are dropped and every retained field is bounded. `pid` is kept as a
    // string of digits only.
    function sanitizeOrigin(origin) {
        var value = origin || {}
        var pid = Logic.cleanField(value.pid, 32)
        if (pid !== "" && !/^[0-9]+$/.test(pid)) pid = ""
        var terminalAncestor = value.terminalAncestor || {}
        return {
            appId: Logic.cleanField(value.appId, Logic.MAX_ID),
            className: Logic.cleanField(value.className !== undefined ? value.className : value.class, Logic.MAX_FIELD),
            initialClass: Logic.cleanField(value.initialClass, Logic.MAX_FIELD),
            desktopEntry: Logic.cleanField(value.desktopEntry, Logic.MAX_ID),
            appName: Logic.cleanField(value.appName, Logic.MAX_FIELD),
            flatpakAppId: Logic.cleanField(value.flatpakAppId, Logic.MAX_ID),
            pid: pid,
            terminal: value.terminal === true,
            terminalAppId: Logic.cleanField(value.terminalAppId, Logic.MAX_ID),
            terminalClass: Logic.cleanField(value.terminalClass, Logic.MAX_FIELD),
            terminalAncestor: {
                appId: Logic.cleanField(terminalAncestor.appId, Logic.MAX_ID),
                className: Logic.cleanField(terminalAncestor.className !== undefined
                    ? terminalAncestor.className : terminalAncestor.class, Logic.MAX_FIELD)
            }
        }
    }

    // ------------------------------------------------------------------
    // Direct metadata lookup
    // ------------------------------------------------------------------

    function applicationsDirs() {
        var dirs = []
        resolverRoot.pushDir(dirs, resolverRoot.xdgDataHome + "/applications")
        var dataDirs = resolverRoot.xdgDataDirs
        for (var i = 0; i < dataDirs.length; i++) {
            resolverRoot.pushDir(dirs, dataDirs[i] + "/applications")
        }
        resolverRoot.pushDir(dirs, "/var/lib/flatpak/exports/share/applications")
        resolverRoot.pushDir(dirs, resolverRoot.home + "/.local/share/flatpak/exports/share/applications")
        return dirs
    }

    function metainfoDirs() {
        var dirs = []
        resolverRoot.pushDir(dirs, "/usr/share/metainfo")
        var dataDirs = resolverRoot.xdgDataDirs
        for (var i = 0; i < dataDirs.length; i++) {
            resolverRoot.pushDir(dirs, dataDirs[i] + "/metainfo")
        }
        // XDG_DATA_HOME is an XDG data directory just like XDG_DATA_DIRS and is
        // searched first for .desktop entries; include its AppStream metainfo
        // root as well so a user-local AppStream-only icon is not skipped.
        resolverRoot.pushDir(dirs, resolverRoot.xdgDataHome + "/metainfo")
        return dirs
    }

    function pushDir(dirs, dir) {
        var value = Logic.cleanField(dir, Logic.MAX_PATH)
        if (value === "" || value.charAt(0) !== "/") return
        for (var i = 0; i < dirs.length; i++) {
            if (dirs[i] === value) return
        }
        dirs.push(value)
    }

    function findDesktopEntry(ids) {
        var dirs = resolverRoot.applicationsDirs()
        for (var d = 0; d < dirs.length; d++) {
            for (var i = 0; i < ids.length; i++) {
                var id = Logic.cleanField(ids[i], Logic.MAX_ID)
                if (id === "" || id.indexOf("/") !== -1 || id.indexOf("..") !== -1) continue
                var path = dirs[d] + "/" + id + ".desktop"
                if (!resolverRoot.metadataFileExists(path)) continue
                var content = resolverRoot.readText(path)
                if (content === "") continue
                var entry = resolverRoot.parseDesktopEntry(content)
                if (entry !== null) return entry
            }
        }
        return null
    }

    // Read only keys from the [Desktop Entry] group. A later action group can
    // legitimately repeat Name=/Icon= (Chromium does); those are not the
    // application identity and must not win.
    function parseDesktopEntry(content) {
        var lines = String(content).split(/\r?\n/)
        var inGroup = false
        var entry = { icon: "", appStreamIcon: "", startupWMClass: "", name: "" }
        var found = false
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === "" || line.charAt(0) === "#") continue
            if (line.charAt(0) === "[") {
                inGroup = line === "[Desktop Entry]"
                continue
            }
            if (!inGroup) continue
            var separator = line.indexOf("=")
            if (separator < 0) continue
            var key = line.substring(0, separator).trim()
            var value = line.substring(separator + 1).trim()
            if (key === "Icon") { entry.icon = value; found = true }
            else if (key === "X-AppStream-Icon") { entry.appStreamIcon = value }
            else if (key === "StartupWMClass") { entry.startupWMClass = value }
            else if (key === "Name" && entry.name === "") { entry.name = value }
        }
        return found ? entry : null
    }

    function findAppStreamIcon(ids) {
        var dirs = resolverRoot.metainfoDirs()
        for (var d = 0; d < dirs.length; d++) {
            for (var i = 0; i < ids.length; i++) {
                var id = Logic.cleanField(ids[i], Logic.MAX_ID)
                if (id === "" || id.indexOf("/") !== -1 || id.indexOf("..") !== -1) continue
                var suffixes = [".metainfo.xml", ".appdata.xml"]
                for (var s = 0; s < suffixes.length; s++) {
                    var path = dirs[d] + "/" + id + suffixes[s]
                    if (!resolverRoot.metadataFileExists(path)) continue
                    var content = resolverRoot.readText(path)
                    if (content === "") continue
                    var icon = resolverRoot.parseAppStreamIcon(content)
                    if (icon !== "") return icon
                }
            }
        }
        return ""
    }

    function parseAppStreamIcon(content) {
        var match = /<icon\b[^>]*>([^<]+)<\/icon>/i.exec(String(content))
        return match ? String(match[1]).trim() : ""
    }

    // Per-app Flatpak export fallback for an icon that is not in the merged
    // exports. Only consulted when the caller supplies a Flatpak app id.
    function flatpakIconFiles(appId, iconValue) {
        var out = []
        var id = Logic.cleanField(appId, Logic.MAX_ID)
        var name = Logic.themeLookupName(iconValue)
        if (id === "" || name === "" || id.indexOf("/") !== -1 || id.indexOf("..") !== -1) return out
        var roots = [
            "/var/lib/flatpak/app/" + id + "/current/active/files/share",
            "/var/lib/flatpak/app/" + id + "/current/active/export/share",
            resolverRoot.home + "/.local/share/flatpak/app/" + id + "/current/active/files/share",
            resolverRoot.home + "/.local/share/flatpak/app/" + id + "/current/active/export/share"
        ]
        var variants = [
            "/icons/hicolor/scalable/apps/" + name + ".svg",
            "/icons/hicolor/256x256/apps/" + name + ".png",
            "/icons/hicolor/128x128/apps/" + name + ".png",
            "/icons/hicolor/64x64/apps/" + name + ".png",
            "/icons/hicolor/48x48/apps/" + name + ".png",
            "/pixmaps/" + name + ".png"
        ]
        for (var r = 0; r < roots.length; r++) {
            for (var v = 0; v < variants.length; v++) {
                var path = roots[r] + variants[v]
                if (resolverRoot.fileUsable(path)) out.push(path)
            }
        }
        return out
    }

    // /proc identity is read as text only: never follow /proc/<pid>/exe, which
    // would pull the binary through the text reader.
    function procExeName(pid) {
        var cmdline = resolverRoot.readText("/proc/" + pid + "/cmdline")
        if (cmdline === "") return ""
        var first = cmdline.split("\u0000")[0]
        return Logic.normalizeExeName(first)
    }

    function collectMetadata(input) {
        var origin = input.origin || {}
        var metadata = {
            desktopIcon: "",
            desktopFound: false,
            startupWMClass: "",
            appstreamIcon: "",
            procExe: "",
            procComm: "",
            flatpakIcons: []
        }
        var ids = Logic.desktopSearchIds(input, metadata)
        var entry = resolverRoot.findDesktopEntry(ids)
        if (entry !== null) {
            metadata.desktopFound = true
            metadata.startupWMClass = entry.startupWMClass
            metadata.desktopIcon = entry.icon !== "" ? entry.icon : entry.appStreamIcon
        }
        // AppStream is only consulted when the direct desktop-entry lookup
        // produced no icon, preserving the chain order.
        if (metadata.desktopIcon === "") {
            metadata.appstreamIcon = resolverRoot.findAppStreamIcon(ids)
        }
        if (origin.flatpakAppId !== "" && metadata.desktopIcon !== "") {
            metadata.flatpakIcons = resolverRoot.flatpakIconFiles(origin.flatpakAppId, metadata.desktopIcon)
        }
        if (origin.pid !== "") {
            metadata.procComm = Logic.cleanField(resolverRoot.readText("/proc/" + origin.pid + "/comm"), Logic.MAX_FIELD)
            metadata.procExe = resolverRoot.procExeName(origin.pid)
        }
        return metadata
    }
}
