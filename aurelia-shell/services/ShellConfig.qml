import QtQuick
import Quickshell
import Quickshell.Io

// The shell owns one small user state document, matching the Omarchy model.
// This service stores only plugin enablement; plugin code and plugin settings
// remain outside the host's implementation. Writes are atomic and blocking so
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

        onSaved: configRoot.lastSaveOk = true
        onSaveFailed: configRoot.lastSaveOk = false
    }

    function defaultConfig() {
        return { version: 1, plugins: [], disabledPlugins: [] }
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
            disabledPlugins: uniqueIds(configRoot.config.disabledPlugins)
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
