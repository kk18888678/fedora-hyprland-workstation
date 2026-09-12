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
    property var barWidgetRegistry: null
    property int revision: 0
    property string lastError: ""
    property bool lastSaveOk: false
    property bool migrationNeeded: false
    property bool migrationInProgress: false
    property string migrationResult: ""
    property string migrationText: ""
    readonly property string migrationBackupPath: configRoot.configPath + ".pre-migration.bak"

    property FileView configFile: FileView {
        path: configRoot.configPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        // A missing first-run config is an expected state handled by reload();
        // do not emit a misleading runtime warning for it.
        printErrors: false

        onSaved: {
            configRoot.lastSaveOk = true
            configRoot.secureConfigPermissions()
        }
        onSaveFailed: {
            configRoot.lastSaveOk = false
            if (configRoot.migrationInProgress) configRoot.finishMigrationSave(false)
        }
        onFileChanged: configRoot.reload()
    }

    property Process migrationBackupProcess: Process {
        id: migrationBackupProcess
        command: [
            "bash",
            "-c",
            "set -Eeuo pipefail; source_path=\"$1\"; backup_path=\"$2\"; " +
            "[[ -f \"$source_path\" && ! -L \"$source_path\" ]] || exit 2; " +
            "if [[ -e \"$backup_path\" || -L \"$backup_path\" ]]; then " +
            "  [[ -f \"$backup_path\" && ! -L \"$backup_path\" ]] || exit 3; " +
            "  exit 0; " +
            "fi; cp -- \"$source_path\" \"$backup_path\"",
            "aurelia-shell-config-migration-backup",
            configRoot.configPath,
            configRoot.migrationBackupPath
        ]

        onExited: function(code) {
            if (code !== 0) {
                configRoot.migrationInProgress = false
                configRoot.migrationResult = "backup-failed"
                configRoot.lastError = "Could not create the recoverable Aurelia shell config migration backup."
                return
            }
            configRoot.configFile.setText(configRoot.migrationText)
        }
    }

    property Process securePermissionProcess: Process {
        id: securePermissionProcess
        command: [
            "bash",
            "-c",
            "set -Eeuo pipefail; target=\"$1\"; " +
            "[[ -f \"$target\" && ! -L \"$target\" ]] || exit 2; " +
            "chmod 600 -- \"$target\"",
            "aurelia-shell-config-secure-permissions",
            configRoot.configPath
        ]

        onExited: function(code) {
            if (code !== 0) {
                configRoot.lastSaveOk = false
                configRoot.lastError = "Could not secure Aurelia shell config permissions."
            }
            if (configRoot.migrationInProgress) configRoot.finishMigrationSave(code === 0)
        }
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

    function cloneJson(value) {
        try {
            return JSON.parse(JSON.stringify(value))
        } catch (e) {
            return null
        }
    }

    function pluginEntryId(entry) {
        if (typeof entry === "string") return entry
        return entry && typeof entry === "object" && !Array.isArray(entry)
            ? entry.id : ""
    }

    function normalizePluginEntries(value) {
        var result = []
        if (!Array.isArray(value)) return result
        for (var i = 0; i < value.length; i++) {
            var entry = value[i]
            var normalized = null
            if (typeof entry === "string") normalized = { id: entry }
            else if (entry && typeof entry === "object" && !Array.isArray(entry)) normalized = cloneJson(entry)
            if (!normalized || !isValidPluginId(normalized.id)) continue
            if (normalized.settings && typeof normalized.settings === "object" &&
                !Array.isArray(normalized.settings)) {
                for (var nestedKey in normalized.settings) {
                    if (normalized[nestedKey] === undefined) normalized[nestedKey] = normalized.settings[nestedKey]
                }
            }
            delete normalized.settings
            result.push(normalized)
        }
        return result
    }

    function normalizeIdle(candidate) {
        if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) return {}
        var normalized = cloneJson(candidate) || {}
        if (normalized.screensaver !== undefined &&
            (typeof normalized.screensaver !== "number" || normalized.screensaver < 0)) delete normalized.screensaver
        if (normalized.lock !== undefined &&
            (typeof normalized.lock !== "number" || normalized.lock < 0)) delete normalized.lock
        return normalized
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
            var allowMultiple = barWidgetRegistry && typeof barWidgetRegistry.allowMultipleFor === "function"
                ? barWidgetRegistry.allowMultipleFor(entry.id) : null
            if (allowMultiple === false) {
                var alreadyPresent = false
                for (var existingIndex = 0; existingIndex < result.length; existingIndex++) {
                    if (result[existingIndex].id === entry.id) {
                        alreadyPresent = true
                        break
                    }
                }
                if (alreadyPresent) continue
            }
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
        var normalized = cloneJson(source) || {}
        var normalizedLayout = cloneJson(sourceLayout) || {}
        normalized.id = barId
        normalized.position = position
        normalized.transparent = source.transparent === true
        normalized.centerAnchor = centerAnchor
        normalizedLayout.left = normalizeBarEntries(sourceLayout.left)
        normalizedLayout.center = normalizeBarEntries(sourceLayout.center)
        normalizedLayout.right = normalizeBarEntries(sourceLayout.right)
        normalized.layout = normalizedLayout
        return normalized
    }

    function defaultConfig() {
        return { version: 1, idle: {}, plugins: [], disabledPlugins: [], bar: defaultBarConfig() }
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
        var known = ["version", "idle", "plugins", "disabledPlugins", "bar"]
        for (var key in candidate) {
            if (known.indexOf(key) === -1) {
                var preserved = cloneJson(candidate[key])
                if (preserved !== null || candidate[key] === null) normalized[key] = preserved
            }
        }
        normalized.idle = candidate.idle === undefined ? {} : normalizeIdle(candidate.idle)
        normalized.plugins = normalizePluginEntries(candidate.plugins)
        normalized.disabledPlugins = uniqueIds(candidate.disabledPlugins)
        normalized.bar = candidate.bar === undefined ? defaultBarConfig() : normalizeBar(candidate.bar)
        return normalized
    }

    property Connections barWidgetRegistryConnection: Connections {
        target: configRoot.barWidgetRegistry
        function onWidgetCatalogChanged() {
            configRoot.config = configRoot.normalize(configRoot.config)
        }
    }

    function serializeConfig(value) {
        return JSON.stringify(value, null, 2) + "\n"
    }

    function finishMigrationSave(success) {
        if (!configRoot.migrationInProgress) return
        configRoot.migrationInProgress = false
        if (!success) {
            configRoot.migrationResult = "write-failed"
            configRoot.lastError = "Could not persist migrated Aurelia shell config."
            return
        }
        configRoot.migrationNeeded = false
        configRoot.migrationResult = "migrated"
        configRoot.migrationText = ""
        configRoot.lastError = ""
        configRoot.revision++
    }

    function secureConfigPermissions() {
        if (!securePermissionProcess.running) securePermissionProcess.running = true
    }

    function migrate() {
        if (configRoot.migrationInProgress) return "pending"
        if (!configRoot.migrationNeeded) {
            configRoot.migrationResult = "not-needed"
            return "ok"
        }
        var current = ""
        try {
            current = configFile.text()
        } catch (e) {
            configRoot.lastError = "Could not read Aurelia shell config for migration."
            configRoot.migrationResult = "read-failed"
            return "error"
        }
        if (current === "") {
            configRoot.migrationNeeded = false
            configRoot.migrationResult = "not-needed"
            return "ok"
        }
        configRoot.migrationText = configRoot.serializeConfig(configRoot.config)
        configRoot.migrationInProgress = true
        configRoot.migrationResult = "backing-up"
        migrationBackupProcess.running = true
        return "pending"
    }

    function reload() {
        var loaded = {}
        var raw = ""
        var sourceWasCanonicalVersion = false
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
                sourceWasCanonicalVersion = loaded && typeof loaded === "object" &&
                    !Array.isArray(loaded) && loaded.version === 1
            } catch (e2) {
                configRoot.lastError = "Malformed Aurelia shell config. Using defaults."
                loaded = {}
            }
        }
        configRoot.config = normalize(loaded)
        configRoot.migrationNeeded = sourceWasCanonicalVersion &&
            raw !== configRoot.serializeConfig(configRoot.config)
        if (!configRoot.migrationNeeded && !configRoot.migrationInProgress &&
            configRoot.migrationResult !== "migrated")
            configRoot.migrationResult = "not-needed"
        configRoot.revision++
    }

    function contains(list, value) {
        return Array.isArray(list) && list.indexOf(value) !== -1
    }

    function containsPluginEntry(list, id) {
        if (!Array.isArray(list)) return false
        for (var i = 0; i < list.length; i++) {
            if (pluginEntryId(list[i]) === id) return true
        }
        return false
    }

    function findPluginEntryIndex(list, id) {
        if (!Array.isArray(list)) return -1
        for (var i = 0; i < list.length; i++) {
            if (pluginEntryId(list[i]) === id) return i
        }
        return -1
    }

    function isPluginEnabled(id, firstParty) {
        if (!isValidPluginId(id)) return false
        if (firstParty) return !contains(configRoot.config.disabledPlugins, id)
        return containsPluginEntry(configRoot.config.plugins, id)
    }

    function setPluginEnabled(id, firstParty, enabled) {
        if (!isValidPluginId(id)) {
            configRoot.lastError = "Invalid plugin id."
            return false
        }

        var next = cloneJson(configRoot.config) || defaultConfig()
        next.version = 1
        next.idle = normalizeIdle(next.idle)
        next.plugins = normalizePluginEntries(next.plugins)
        next.disabledPlugins = uniqueIds(next.disabledPlugins)
        next.bar = normalizeBar(next.bar)
        var list = firstParty ? next.disabledPlugins : next.plugins
        var index = firstParty ? list.indexOf(id) : findPluginEntryIndex(list, id)
        if (enabled) {
            if (firstParty) {
                if (index !== -1) list.splice(index, 1)
            } else if (index === -1) {
                list.push({ id: id })
            }
        } else {
            if (firstParty) {
                if (index === -1) list.push(id)
            } else if (index !== -1) {
                list.splice(index, 1)
            }
        }
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
