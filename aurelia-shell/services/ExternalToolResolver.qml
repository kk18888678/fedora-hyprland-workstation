pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Deterministic external-tool resolver. Single owner for "which absolute
// binary should a shell-spawned process execute, and what PATH should it
// inherit?".
//
// The compositor-inherited PATH is NEVER trusted as the primary source. It is
// only appended after the deterministic directories as a last-resort suffix.
// The Python helper `bin/workstation-notification-focus` mirrors this exact
// search order in `resolve_tool`; both forms must be changed together.
//
// Search order, first hit wins:
//   1. explicit override `AURELIA_TOOL_<TOOL>_BIN` (validated absolute)
//   2. <shell root>/bin/<tool>
//   3. <shell root>/../bin/<tool>
//   4. ~/.local/bin/<tool>
//   5. ~/.nix-profile/bin/<tool>
//   6. /nix/var/nix/profiles/default/bin/<tool>
//   7. /usr/local/bin/<tool>, /usr/bin/<tool>, /bin/<tool>
//   8. inherited PATH (suffix only)
//
// `resolve` returns `{ path, available, searched, failureClass }` where
// `available: false` is a first-class outcome. A missing tool is reported
// through the existing failure-class vocabulary (`tooling-unavailable`), never
// silently skipped. Availability is proven by a bounded, read-only probe that
// validates an explicit override and otherwise asks the shell's `type -P` to
// resolve each tool against the deterministic PATH; the probe never executes
// the resolved tool.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string inheritedPath: Quickshell.env("PATH") || ""

    // Cached probe results keyed by tool name: { path, available }.
    property var toolCache: ({})
    property string cacheShellRoot: ""
    property bool toolsProbeRunning: false
    property bool toolsProbeComplete: false
    property string toolsProbeFailureClass: ""

    property Process toolsProbe: Process {
        running: false
        stdout: SplitParser {
            onRead: function(line) { root.ingestProbeLine(line) }
        }
        onExited: function(code) {
            root.toolsProbeRunning = false
            root.toolsProbeComplete = true
            if (code !== 0) {
                root.toolsProbeFailureClass = code === 127
                    ? "tooling-unavailable" : "resolver-probe-exited"
                console.warn("[TOOL-RESOLVER] probe failed code=" + code +
                    " class=" + root.toolsProbeFailureClass)
                return
            }
            root.toolsProbeFailureClass = ""
        }
    }

    Component.onDestruction: {
        root.toolsProbe.running = false
    }

    function overrideEnvName(tool) {
        return "AURELIA_TOOL_" + String(tool || "").toUpperCase().replace(/-/g, "_") + "_BIN"
    }

    // An explicit override is validated absolute and wins outright. It is the
    // documented test seam and a deliberate operator decision; the probe checks
    // it is an executable regular file so a stale override fails closed.
    function overridePath(tool) {
        var value = Quickshell.env(root.overrideEnvName(tool)) || ""
        return (value.charAt(0) === "/" && value !== "/") ? value : ""
    }

    function shellRoot(shellRootValue) {
        var candidate = (shellRootValue === undefined || shellRootValue === null)
            ? "" : String(shellRootValue)
        if (candidate === "") candidate = Quickshell.env("AURELIA_SHELL_ROOT") || ""
        if (candidate.charAt(0) !== "/" || candidate === "/") return ""
        return candidate.replace(/\/+$/, "")
    }

    function searchDirs(shellRootValue) {
        var dirs = []
        var base = root.shellRoot(shellRootValue)
        if (base !== "") {
            dirs.push(base + "/bin")
            dirs.push(base + "/../bin")
        }
        if (root.home.charAt(0) === "/" && root.home !== "/") {
            dirs.push(root.home.replace(/\/+$/, "") + "/.local/bin")
            dirs.push(root.home.replace(/\/+$/, "") + "/.nix-profile/bin")
        }
        dirs.push("/nix/var/nix/profiles/default/bin")
        dirs.push("/usr/local/bin")
        dirs.push("/usr/bin")
        dirs.push("/bin")
        return dirs
    }

    function candidates(tool, shellRootValue) {
        var name = String(tool || "")
        if (name === "" || name.indexOf("/") !== -1) return []
        var override = root.overridePath(name)
        if (override !== "") return [override]
        var list = []
        var dirs = root.searchDirs(shellRootValue)
        for (var i = 0; i < dirs.length; i++) {
            var candidate = dirs[i] + "/" + name
            if (list.indexOf(candidate) === -1) list.push(candidate)
        }
        var inherited = root.inheritedPath.split(":")
        for (var j = 0; j < inherited.length; j++) {
            if (inherited[j] === "") continue
            var path = inherited[j] + "/" + name
            if (list.indexOf(path) === -1) list.push(path)
        }
        return list
    }

    function resolve(tool, shellRootValue) {
        var name = String(tool || "")
        if (name === "" || name.indexOf("/") !== -1) {
            return { path: "", available: false, searched: [], failureClass: "tooling-unavailable" }
        }
        var searched = root.candidates(name, shellRootValue)
        var cacheMatches = root.cacheShellRoot === root.shellRoot(shellRootValue) &&
            root.toolCache[name] !== undefined
        var cached = cacheMatches ? root.toolCache[name] : null
        if (root.overridePath(name) !== "") {
            // The probe validates the override fail-closed. Until it completes,
            // the override is reported unavailable rather than assumed present.
            var overridePath = String(cached ? (cached.path || "") : "")
            var overrideAvailable = cached !== null && cached.available === true
            return {
                path: overrideAvailable ? overridePath : "",
                available: overrideAvailable,
                searched: searched,
                failureClass: overrideAvailable ? "" : "tooling-unavailable"
            }
        }
        if (cacheMatches) {
            return {
                path: String(cached.path || ""),
                available: cached.available === true,
                searched: searched,
                failureClass: cached.available === true ? "" : "tooling-unavailable"
            }
        }
        return {
            path: "",
            available: false,
            searched: searched,
            failureClass: "tooling-unavailable"
        }
    }

    function ingestProbeLine(line) {
        var text = String(line || "")
        var separator = text.indexOf("=")
        if (separator <= 0) return
        var name = text.substring(0, separator)
        var path = text.substring(separator + 1)
        var cache = root.toolCache
        cache[name] = { path: path, available: path !== "" }
        root.toolCache = cache
    }

    // Deterministic PATH string: deterministic directories first, inherited
    // PATH appended only as a suffix.
    function pathValue(shellRootValue) {
        var parts = []
        var dirs = root.searchDirs(shellRootValue)
        for (var i = 0; i < dirs.length; i++) {
            if (dirs[i] !== "" && parts.indexOf(dirs[i]) === -1) parts.push(dirs[i])
        }
        if (root.inheritedPath !== "") parts.push(root.inheritedPath)
        return parts.join(":")
    }

    // The environment every shell-spawned process must receive. It generalises
    // the pattern previously duplicated in AgentsBarWidget.processEnvironment.
    function environment(shellRootValue) {
        return {
            "PATH": root.pathValue(shellRootValue),
            "HOME": root.home,
            "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || "",
            "XDG_STATE_HOME": Quickshell.env("XDG_STATE_HOME") || "",
            "XDG_CONFIG_HOME": Quickshell.env("XDG_CONFIG_HOME") || "",
            "XDG_CACHE_HOME": Quickshell.env("XDG_CACHE_HOME") || ""
        }
    }

    // Probe one batch of tool names. Each override is validated as an absolute
    // executable regular file first; otherwise `type -P` resolves the tool
    // against the deterministic PATH. This is read-only and bounded; it never
    // runs the resolved tool. The override env name is passed literally so an
    // arbitrary override value is never interpolated into the script.
    function beginProbe(tools, shellRootValue) {
        var names = []
        for (var i = 0; i < (tools ? tools.length : 0); i++) {
            var name = String(tools[i] || "")
            if (name === "" || name.indexOf("/") !== -1) continue
            if (names.indexOf(name) === -1) names.push(name)
        }
        if (names.length === 0) return false
        root.cacheShellRoot = root.shellRoot(shellRootValue)
        var seeded = {}
        for (var j = 0; j < names.length; j++) seeded[names[j]] = { path: "", available: false }
        root.toolCache = seeded
        root.toolsProbeComplete = false
        root.toolsProbeFailureClass = ""
        var script = "check_tool() { local tool=\"$1\" override=\"$2\" p=\"\"; " +
            "if [ -n \"$override\" ]; then " +
            "if [ \"${override#/}\" != \"$override\" ] && [ \"$override\" != \"/\" ] && [ -f \"$override\" ] && [ -x \"$override\" ]; then p=\"$override\"; else p=\"\"; fi; " +
            "else p=\"$(type -P -- \"$tool\")\" || p=\"\"; fi; " +
            "printf '%s=%s\\n' \"$tool\" \"$p\"; }; "
        for (var k = 0; k < names.length; k++) {
            script += "check_tool " + names[k] + " \"$" + root.overrideEnvName(names[k]) + "\"; "
        }
        root.toolsProbe.command = ["/usr/bin/bash", "-c", script]
        root.toolsProbe.environment = root.environment(shellRootValue)
        root.toolsProbe.running = true
        root.toolsProbeRunning = true
        return true
    }
}
