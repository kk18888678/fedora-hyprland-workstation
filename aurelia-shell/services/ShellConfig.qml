import QtQuick
import Quickshell
import Quickshell.Io

// The shell owns one small user state document, matching the Omarchy model.
// This service stores plugin enablement and the small shared bar layout
// contract; plugin code and plugin settings remain outside the host's
// implementation. Writes are atomic and blocking so
// an IPC caller never receives success for an unpersisted state transition.
QtObject {
    id: configRoot

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHomeOverride: Quickshell.env("XDG_CONFIG_HOME") || ""
    readonly property string configHome: configHomeOverride.charAt(0) === "/" ? configHomeOverride : (home + "/.config")
    readonly property string configuredPath: Quickshell.env("AURELIA_SHELL_CONFIG") || ""
    readonly property string configPath: {
        if (configuredPath !== "" && configuredPath.charAt(0) === "/") return configuredPath
        return configHome + "/aurelia/shell.json"
    }

    property var config: ({ version: 1, plugins: [], disabledPlugins: [] })
    property int revision: 0
    property string lastError: ""
    property bool lastSaveOk: false

    property FileView configFile: FileView {
        path: configRoot.configPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        // A missing first-run config is an expected state handled by reload();
        // do not emit a misleading runtime warning for it.
        printErrors: false

        onSaved: configRoot.lastSaveOk = true
        onSaveFailed: configRoot.lastSaveOk = false
        onFileChanged: configRoot.reload()
    }

    function defaultBarConfig() {
        return {
            id: "aurelia.bar",
            position: "top",
            transparent: false,
            centerAnchor: "aurelia.clock",
            layout: {
                left: [{ id: "aurelia.workspaces" }],
                center: [
                    { id: "aurelia.notifications" },
                    { id: "aurelia.clock", format: "MMM d, dddd HH:mm" },
                    { id: "aurelia.weather", location: "auto" }
                ],
                right: [
                    { id: "aurelia.tray" },
                    { id: "aurelia.network" },
                    { id: "aurelia.bluetooth" },
                    { id: "aurelia.monitor" },
                    { id: "aurelia.screenshot" },
                    { id: "aurelia.power" }
                ]
            }
        }
    }

    function cloneEntrySettings(entry) {
        var result = {}
        if (!entry || typeof entry !== "object" || Array.isArray(entry)) return result
        for (var key in entry) {
            if (key !== "id" && key !== "settings") result[key] = entry[key]
        }
        // Accept the earlier Aurelia nested shape while writing the Omarchy-
        // compatible inline shape going forward.
        var nested = entry.settings
        if (nested && typeof nested === "object" && !Array.isArray(nested)) {
            for (var nestedKey in nested) {
                if (result[nestedKey] === undefined) result[nestedKey] = nested[nestedKey]
            }
        }
        return result
    }

    function normalizeBarEntries(value) {
        var result = []
        if (!Array.isArray(value)) return result
        for (var i = 0; i < value.length; i++) {
            var entry = value[i]
            if (typeof entry === "string") entry = { id: entry }
            if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
            if (!isValidPluginId(entry.id)) continue
            var normalizedEntry = cloneEntrySettings(entry)
            normalizedEntry.id = entry.id
            result.push(normalizedEntry)
        }
        return result
    }

    function normalizeBar(candidate) {
        var source = candidate && typeof candidate === "object" && !Array.isArray(candidate) ? candidate : {}
        var sourceLayout = source.layout && typeof source.layout === "object" && !Array.isArray(source.layout) ? source.layout : {}
        var barId = isValidPluginId(source.id) ? source.id : "aurelia.bar"
        var position = ["top", "bottom", "left", "right"].indexOf(source.position) !== -1
            ? source.position
            : "top"
        var centerAnchor = isValidPluginId(source.centerAnchor) ? source.centerAnchor : ""
        return {
            id: barId,
            position: position,
            transparent: source.transparent === true,
            centerAnchor: centerAnchor,
            layout: {
                left: normalizeBarEntries(sourceLayout.left),
                center: normalizeBarEntries(sourceLayout.center),
                right: normalizeBarEntries(sourceLayout.right)
            }
        }
    }

    function defaultConfig() {
        return { version: 1, plugins: [], disabledPlugins: [], bar: defaultBarConfig() }
    }

    function isValidPluginId(value) {
        return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value) && value.indexOf("..") === -1
    }

    function uniqueIds(value) {
        var result = []
        var seen = {}
        if (!Array.isArray(value)) return result
        for (var i = 0; i < value.length; i++) {
            if (!isValidPluginId(value[i]) || seen[value[i]]) continue
            seen[value[i]] = true
            result.push(value[i])
        }
        result.sort()
        return result
    }

    function normalize(candidate) {
        var normalized = defaultConfig()
        if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) return normalized
        if (candidate.version !== undefined && candidate.version !== 1) {
            configRoot.lastError = "Unsupported Aurelia shell config version. Using defaults."
            return normalized
        }
        normalized.plugins = uniqueIds(candidate.plugins)
        normalized.disabledPlugins = uniqueIds(candidate.disabledPlugins)
        normalized.bar = candidate.bar === undefined ? defaultBarConfig() : normalizeBar(candidate.bar)
        return normalized
    }

    function reload() {
        var loaded = {}
        var raw = ""
        configRoot.lastError = ""
        try {
            raw = configFile.text()
        } catch (e) {
            raw = ""
            configRoot.lastError = "Could not read Aurelia shell config. Using defaults."
        }

        if (raw && raw.trim() !== "") {
            try {
                loaded = JSON.parse(raw)
            } catch (e2) {
                configRoot.lastError = "Malformed Aurelia shell config. Using defaults."
                loaded = {}
            }
        }
        configRoot.config = normalize(loaded)
        configRoot.revision++
    }

    function contains(list, value) {
        return Array.isArray(list) && list.indexOf(value) !== -1
    }

    function isPluginEnabled(id, firstParty) {
        if (!isValidPluginId(id)) return false
        if (firstParty) return !contains(configRoot.config.disabledPlugins, id)
        return contains(configRoot.config.plugins, id)
    }

    function setPluginEnabled(id, firstParty, enabled) {
        if (!isValidPluginId(id)) {
            configRoot.lastError = "Invalid plugin id."
            return false
        }

        var next = {
            version: 1,
            plugins: uniqueIds(configRoot.config.plugins),
            disabledPlugins: uniqueIds(configRoot.config.disabledPlugins),
            bar: normalizeBar(configRoot.config.bar)
        }
        var list = firstParty ? next.disabledPlugins : next.plugins
        var index = list.indexOf(id)
        if (enabled) {
            if (firstParty) {
                if (index !== -1) list.splice(index, 1)
            } else if (index === -1) {
                list.push(id)
            }
        } else {
            if (firstParty) {
                if (index === -1) list.push(id)
            } else if (index !== -1) {
                list.splice(index, 1)
            }
        }
        next.plugins.sort()
        next.disabledPlugins.sort()

        var serialized = JSON.stringify(next, null, 2) + "\n"
        var previous = configRoot.config
        var current = ""
        try {
            current = configFile.text()
        } catch (e) {}
        if (current === serialized) {
            configRoot.config = next
            return true
        }

        configRoot.lastSaveOk = false
        configRoot.config = next
        configFile.setText(serialized)
        if (!configRoot.lastSaveOk) {
            configRoot.config = previous
            configRoot.lastError = "Could not persist Aurelia shell config."
            return false
        }
        configRoot.lastError = ""
        configRoot.revision++
        return true
    }

    Component.onCompleted: configRoot.reload()
}
