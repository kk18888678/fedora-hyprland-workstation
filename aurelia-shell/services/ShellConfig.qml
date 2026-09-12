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
    property PluginCloneState cloneState: PluginCloneState { owner: configRoot }
    property int revision: 0
    property string lastError: ""
    property bool lastSaveOk: false
    property bool lastMutationChanged: false
    property bool migrationNeeded: false
    property bool migrationInProgress: false
    property string migrationResult: ""
    property string migrationText: ""
    readonly property int settingsMaxBytes: 65536
    readonly property int settingsMaxDepth: 8
    readonly property int settingsMaxNodes: 512
    readonly property int settingsMaxKeys: 64
    readonly property int settingsMaxArrayLength: 128
    readonly property int settingsMaxStringLength: 4096
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

    function isPlainObject(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value)
    }

    function objectHas(value, key) {
        return configRoot.isPlainObject(value) && Object.keys(value).indexOf(String(key)) !== -1
    }

    function prepareMutationConfig() {
        var next = configRoot.cloneJson(configRoot.config)
        if (!configRoot.isPlainObject(next)) next = configRoot.defaultConfig()
        next.version = 1
        next.idle = configRoot.normalizeIdle(next.idle)
        next.plugins = configRoot.normalizePluginEntries(next.plugins)
        next.disabledPlugins = configRoot.uniqueIds(next.disabledPlugins)
        next.bar = configRoot.normalizeBar(next.bar)
        if (configRoot.objectHas(next, "cloneSourceRestores")) {
            next.cloneSourceRestores = configRoot.cloneState.normalizeCloneSourceRestores(next.cloneSourceRestores)
            if (next.cloneSourceRestores.length === 0) delete next.cloneSourceRestores
        }
        return next
    }

    function persistConfig(next) {
        var serialized = configRoot.serializeConfig(next)
        var previous = configRoot.config
        var current = ""
        try {
            current = configRoot.configFile.text()
        } catch (e) {}
        if (current === serialized) {
            configRoot.config = next
            configRoot.lastSaveOk = true
            configRoot.lastMutationChanged = false
            configRoot.lastError = ""
            return true
        }

        configRoot.lastSaveOk = false
        configRoot.lastMutationChanged = true
        configRoot.config = next
        configRoot.configFile.setText(serialized)
        if (!configRoot.lastSaveOk) {
            configRoot.config = previous
            configRoot.lastError = "Could not persist Aurelia shell config."
            return false
        }
        configRoot.lastError = ""
        configRoot.revision++
        return true
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

    function isSafeSettingKey(value) {
        return typeof value === "string" && /^[A-Za-z][A-Za-z0-9_.-]*$/.test(value)
    }

    function validateJsonValue(value, depth, counters) {
        counters.nodes++
        if (counters.nodes > configRoot.settingsMaxNodes || depth > configRoot.settingsMaxDepth) return false
        if (value === null) return true
        if (typeof value === "string") return value.length <= configRoot.settingsMaxStringLength
        if (typeof value === "boolean") return true
        if (typeof value === "number") return isFinite(value)
        if (typeof value !== "object" || typeof value === "function" || typeof value === "undefined") return false

        if (Array.isArray(value)) {
            if (value.length > configRoot.settingsMaxArrayLength) return false
            for (var arrayIndex = 0; arrayIndex < value.length; arrayIndex++)
                if (!configRoot.validateJsonValue(value[arrayIndex], depth + 1, counters)) return false
            return true
        }
        if (!configRoot.isPlainObject(value)) return false
        var keys = Object.keys(value)
        if (keys.length > configRoot.settingsMaxKeys) return false
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            if (!configRoot.isSafeSettingKey(keys[keyIndex])) return false
            if (!configRoot.validateJsonValue(value[keys[keyIndex]], depth + 1, counters)) return false
        }
        return true
    }

    function validateSettingsObject(value) {
        if (!configRoot.isPlainObject(value)) return {ok: false, error: "settings must be a JSON object"}
        var keys = Object.keys(value)
        var counters = {nodes: 0}
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            var key = keys[keyIndex]
            if (["id", "instanceId", "settings"].indexOf(key) !== -1 ||
                !configRoot.isSafeSettingKey(key))
                return {ok: false, error: "invalid setting key: " + key}
            if (!configRoot.validateJsonValue(value[key], 1, counters))
                return {ok: false, error: "setting value is not bounded JSON: " + key}
        }
        var serialized = ""
        try {
            serialized = JSON.stringify(value)
        } catch (e) {
            return {ok: false, error: "settings must be serializable JSON"}
        }
        if (typeof serialized !== "string" || serialized.length > configRoot.settingsMaxBytes)
            return {ok: false, error: "settings exceed the bounded JSON size"}
        var copy = configRoot.cloneJson(value)
        if (!configRoot.isPlainObject(copy)) return {ok: false, error: "settings must be serializable JSON"}
        return {ok: true, value: copy}
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
        var known = ["version", "idle", "plugins", "disabledPlugins", "bar", "cloneSourceRestores"]
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
        if (objectHas(candidate, "cloneSourceRestores")) {
            normalized.cloneSourceRestores = configRoot.cloneState.normalizeCloneSourceRestores(candidate.cloneSourceRestores)
            if (normalized.cloneSourceRestores.length === 0) delete normalized.cloneSourceRestores
        }
        return normalized
    }

    property Connections barWidgetRegistryConnection: Connections {
        target: configRoot.barWidgetRegistry
        function onWidgetCatalogChanged() {
            var normalized = configRoot.normalize(configRoot.config)
            if (configRoot.serializeConfig(normalized) !== configRoot.serializeConfig(configRoot.config))
                configRoot.config = normalized
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

    function pluginEntryInstanceId(entry) {
        var id = pluginEntryId(entry)
        var configured = isPlainObject(entry) ? entry.instanceId : ""
        return typeof configured === "string" && isValidPluginId(configured) ? configured : id
    }

    function findPluginEntryLocation(config, id) {
        var requested = String(id || "")
        if (!isPlainObject(config) || !Array.isArray(config.plugins)) return {found: false}
        var exact = []
        var base = []
        for (var i = 0; i < config.plugins.length; i++) {
            var entry = config.plugins[i]
            var location = {found: true, kind: "plugin", index: i}
            if (pluginEntryInstanceId(entry) === requested) exact.push(location)
            if (pluginEntryId(entry) === requested) base.push(location)
        }
        if (exact.length > 1 || (exact.length === 0 && base.length > 1))
            return {found: false, error: "ambiguous plugin " + requested}
        if (exact.length === 1) return exact[0]
        if (base.length === 1) return base[0]
        return {found: false}
    }

    function validateSettingsSelector(value) {
        var selectorResult = validatePlacement(value, true)
        if (!selectorResult.ok) return selectorResult
        var selector = selectorResult.value
        if (objectHas(selector, "before") || objectHas(selector, "after"))
            return {ok: false, error: "settings selectors do not accept before or after"}
        if (objectHas(selector, "section") && objectHas(selector, "fromSection"))
            return {ok: false, error: "settings selectors accept only one of section or from-section"}
        if (objectHas(selector, "index") && objectHas(selector, "fromIndex"))
            return {ok: false, error: "settings selectors accept only one of index or from-index"}
        if (objectHas(selector, "index") && !objectHas(selector, "section"))
            return {ok: false, error: "index requires section"}
        return {ok: true, value: selector}
    }

    function barLookupSelector(selector) {
        var lookup = cloneJson(selector) || ({})
        if (objectHas(lookup, "section")) {
            lookup.fromSection = lookup.section
            delete lookup.section
        }
        if (objectHas(lookup, "index")) {
            lookup.fromIndex = lookup.index
            delete lookup.index
        }
        return lookup
    }

    function findConfigEntry(config, id, selector) {
        var requested = String(id || "")
        if (!isValidPluginId(requested)) return {found: false, error: "Invalid plugin id: " + requested}
        var selected = selector || ({})
        var hasBarSelector = objectHas(selected, "section") || objectHas(selected, "index") ||
            objectHas(selected, "fromSection") || objectHas(selected, "fromIndex")
        if (hasBarSelector) {
            var barLocation = resolveBarLocation(config, requested, barLookupSelector(selected))
            if (!barLocation.found) return barLocation
            return {found: true, kind: "bar", section: barLocation.section, index: barLocation.index}
        }

        var bar = findBarLocation(config, requested, "")
        if (bar.error) return bar
        if (bar.found) return {found: true, kind: "bar", section: bar.section, index: bar.index}
        var plugin = findPluginEntryLocation(config, requested)
        if (plugin.error) return plugin
        if (plugin.found) return plugin
        return {found: false, error: "could not find configured plugin " + requested}
    }

    function barEntryId(entry) {
        if (typeof entry === "string") return entry
        return configRoot.isPlainObject(entry) && typeof entry.id === "string" ? entry.id : ""
    }

    function barEntryInstanceId(entry) {
        var id = configRoot.barEntryId(entry)
        if (configRoot.barWidgetRegistry && typeof configRoot.barWidgetRegistry.instanceIdFor === "function")
            return configRoot.barWidgetRegistry.instanceIdFor(id, entry)
        return id
    }

    function findBarLocation(config, id, section) {
        var requested = String(id || "")
        if (!configRoot.isValidPluginId(requested)) return {found: false, error: "Invalid widget id: " + requested}
        if (!configRoot.isPlainObject(config) || !configRoot.isPlainObject(config.bar) ||
            !configRoot.isPlainObject(config.bar.layout)) return {found: false}

        var sections = ["left", "center", "right"]
        var exact = []
        var base = []
        for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
            var currentSection = sections[sectionIndex]
            if (section && currentSection !== section) continue
            var entries = config.bar.layout[currentSection]
            if (!Array.isArray(entries)) continue
            for (var entryIndex = 0; entryIndex < entries.length; entryIndex++) {
                var entry = entries[entryIndex]
                var location = {found: true, section: currentSection, index: entryIndex}
                if (configRoot.barEntryInstanceId(entry) === requested) exact.push(location)
                if (configRoot.barEntryId(entry) === requested) base.push(location)
            }
        }
        if (exact.length > 1 || (exact.length === 0 && base.length > 1))
            return {found: false, error: "ambiguous widget " + requested}
        if (exact.length === 1) return exact[0]
        if (base.length === 1) return base[0]
        return {found: false}
    }

    function barLocationAt(config, section, index) {
        var entries = config && config.bar && config.bar.layout ? config.bar.layout[section] : null
        if (!Array.isArray(entries) || index < 0 || index >= entries.length)
            return {found: false, error: "no widget at " + section + "[" + index + "]"}
        return {found: true, section: section, index: index}
    }

    function entryMatchesWidget(entry, id) {
        var requested = String(id || "")
        return configRoot.barEntryId(entry) === requested || configRoot.barEntryInstanceId(entry) === requested
    }

    function isBarSection(value) {
        return typeof value === "string" && ["left", "center", "right"].indexOf(value) !== -1
    }

    function isNonNegativeInteger(value) {
        return typeof value === "number" && isFinite(value) && value >= 0 && Math.floor(value) === value
    }

    function validatePlacement(value, allowFrom) {
        var placement = value === undefined || value === null ? ({}) : configRoot.cloneJson(value)
        if (!configRoot.isPlainObject(placement)) return {ok: false, error: "placement must be an object"}
        var allowed = ["section", "index", "before", "after"]
        if (allowFrom) allowed = allowed.concat(["fromSection", "fromIndex"])
        var keys = Object.keys(placement)
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            if (allowed.indexOf(keys[keyIndex]) === -1)
                return {ok: false, error: "unknown placement option: " + keys[keyIndex]}
        }
        if (configRoot.objectHas(placement, "section") && !configRoot.isBarSection(placement.section))
            return {ok: false, error: "section must be left, center, or right"}
        if (configRoot.objectHas(placement, "index") && !configRoot.isNonNegativeInteger(placement.index))
            return {ok: false, error: "index must be a non-negative integer"}
        if (configRoot.objectHas(placement, "before") && configRoot.objectHas(placement, "after"))
            return {ok: false, error: "use only one of before or after"}
        if (configRoot.objectHas(placement, "before") && !configRoot.isValidPluginId(placement.before))
            return {ok: false, error: "before requires a valid widget id"}
        if (configRoot.objectHas(placement, "after") && !configRoot.isValidPluginId(placement.after))
            return {ok: false, error: "after requires a valid widget id"}
        if (allowFrom && configRoot.objectHas(placement, "fromSection") &&
            !configRoot.isBarSection(placement.fromSection))
            return {ok: false, error: "from-section must be left, center, or right"}
        if (allowFrom && configRoot.objectHas(placement, "fromIndex") &&
            !configRoot.isNonNegativeInteger(placement.fromIndex))
            return {ok: false, error: "from-index must be a non-negative integer"}
        if (allowFrom && configRoot.objectHas(placement, "fromIndex") &&
            !configRoot.objectHas(placement, "fromSection"))
            return {ok: false, error: "from-index requires from-section"}
        if (!allowFrom && (configRoot.objectHas(placement, "fromSection") ||
            configRoot.objectHas(placement, "fromIndex")))
            return {ok: false, error: "this operation does not accept source selectors"}
        return {ok: true, value: placement}
    }

    function barTarget(config, placement, fallbackSection) {
        var target = placement || ({})
        var section = configRoot.objectHas(target, "section") ? target.section : fallbackSection
        if (!configRoot.isBarSection(section)) return {error: "section must be left, center, or right"}
        var entries = config.bar.layout[section]
        if (!Array.isArray(entries)) {
            config.bar.layout[section] = []
            entries = config.bar.layout[section]
        }

        var relativeId = configRoot.objectHas(target, "before") ? target.before :
            (configRoot.objectHas(target, "after") ? target.after : "")
        if (relativeId) {
            var relativeSection = configRoot.objectHas(target, "section") ? section : ""
            var relative = configRoot.findBarLocation(config, relativeId, relativeSection)
            if (relative.error) return {error: relative.error}
            if (!relative.found) return {error: "could not find target widget " + relativeId}
            return {
                section: relative.section,
                index: relative.index + (configRoot.objectHas(target, "after") ? 1 : 0)
            }
        }
        if (configRoot.objectHas(target, "index"))
            return {section: section, index: Math.min(target.index, entries.length)}

        var anchors = {left: "aurelia.workspaces", center: "aurelia.weather", right: "aurelia.tray"}
        var anchor = configRoot.findBarLocation(config, anchors[section], section)
        return {
            section: section,
            index: anchor.found ? anchor.index + 1 : entries.length
        }
    }

    function resolveBarLocation(config, id, placement) {
        if (configRoot.objectHas(placement, "fromIndex")) {
            var from = configRoot.barLocationAt(config, placement.fromSection, placement.fromIndex)
            if (!from.found) return from
            if (!configRoot.entryMatchesWidget(config.bar.layout[from.section][from.index], id))
                return {found: false, error: "widget at " + from.section + "[" + from.index + "] is not " + id}
            return from
        }
        var section = configRoot.objectHas(placement, "fromSection") ? placement.fromSection : ""
        var location = configRoot.findBarLocation(config, id, section)
        if (location.error) return location
        return location.found ? location : {found: false, error: "could not find widget " + id}
    }

    function moveBarEntry(config, id, placement) {
        var source = configRoot.resolveBarLocation(config, id, placement)
        if (!source.found) return source.error
        var entry = configRoot.cloneJson(config.bar.layout[source.section][source.index])
        if (!configRoot.isPlainObject(entry)) return "widget entry must be an object"
        config.bar.layout[source.section].splice(source.index, 1)
        var target = configRoot.barTarget(config, placement, source.section)
        if (target.error) {
            config.bar.layout[source.section].splice(source.index, 0, entry)
            return target.error
        }
        config.bar.layout[target.section].splice(target.index, 0, entry)
        return ""
    }

    function removeDisabledId(list, id) {
        if (!Array.isArray(list)) return []
        var result = []
        for (var i = 0; i < list.length; i++) if (list[i] !== id) result.push(list[i])
        return result
    }

    function enableBarPluginInConfig(config, id, firstParty, isBarWidget, hasNonWidgetKind,
                                     defaultSection, placement, putOnly) {
        config.disabledPlugins = configRoot.removeDisabledId(config.disabledPlugins, id)
        if (!isBarWidget) {
            if (!firstParty && !configRoot.containsPluginEntry(config.plugins, id)) config.plugins.push({id: id})
            return ""
        }

        var location = configRoot.findBarLocation(config, id, "")
        if (location.error) return location.error
        if (!location.found) {
            var target = configRoot.barTarget(config, placement, configRoot.isBarSection(defaultSection)
                ? defaultSection : "center")
            if (target.error && putOnly && target.error.indexOf("could not find target widget ") === 0) {
                var fallbackPlacement = configRoot.cloneJson(placement) || ({})
                delete fallbackPlacement.before
                delete fallbackPlacement.after
                target = configRoot.barTarget(config, fallbackPlacement, configRoot.isBarSection(defaultSection)
                    ? defaultSection : "center")
            }
            if (target.error) return target.error
            config.bar.layout[target.section].splice(target.index, 0, {id: id})
        } else if (!putOnly && Object.keys(placement || ({})).length > 0) {
            var moveError = configRoot.moveBarEntry(config, id, placement)
            if (moveError) return moveError
        }

        if (!firstParty && hasNonWidgetKind && !configRoot.containsPluginEntry(config.plugins, id))
            config.plugins.push({id: id})
        return ""
    }

    function enablePlugin(id, firstParty, isBarWidget, hasNonWidgetKind, defaultSection, placement, putOnly, isBarOption, cloneSourceId) {
        if (!configRoot.isValidPluginId(id)) return "Invalid plugin id: " + id
        var placementResult = configRoot.validatePlacement(placement, false)
        if (!placementResult.ok) return placementResult.error
        var next = configRoot.prepareMutationConfig()
        var originId = String(cloneSourceId || "")
        if (originId !== "" && (firstParty === true || !configRoot.isValidPluginId(originId) || originId === String(id)))
            return "Invalid clone source: " + originId

        var error = ""
        if (originId !== "") {
            error = configRoot.cloneState.enableClonePluginInConfig(next, id, originId, isBarWidget === true,
                hasNonWidgetKind === true, defaultSection, placementResult.value, putOnly === true,
                isBarOption === true)
        } else {
            if (firstParty === true) {
                var activeClone = configRoot.cloneState.cloneSourceRestoreForSource(next, id)
                if (activeClone) {
                    error = configRoot.cloneState.restoreCloneInConfig(next, activeClone.cloneId, id)
                    if (error) return error
                }
            }
            if (isBarOption === true) {
                if (Object.keys(placementResult.value).length > 0) return "bar options do not accept widget placement"
                next.disabledPlugins = configRoot.removeDisabledId(next.disabledPlugins, id)
                next.bar.id = id
            } else {
                error = configRoot.enableBarPluginInConfig(next, id, firstParty === true, isBarWidget === true,
                    hasNonWidgetKind === true, defaultSection, placementResult.value, putOnly === true)
            }
        }
        if (error) return error
        if (!configRoot.persistConfig(next)) return configRoot.lastError || "Could not persist Aurelia shell config."
        return ""
    }

    function setPluginEnabled(id, firstParty, enabled, isBarWidget, cloneSourceId) {
        return configRoot.cloneState.setPluginEnabled(id, firstParty, enabled, isBarWidget, cloneSourceId)
    }

    function moveBarWidget(id, placement) {
        if (!configRoot.isValidPluginId(id)) return "Invalid widget id: " + id
        var placementResult = configRoot.validatePlacement(placement, true)
        if (!placementResult.ok) return placementResult.error
        var next = configRoot.prepareMutationConfig()
        var error = configRoot.moveBarEntry(next, id, placementResult.value)
        if (error) return error
        if (!configRoot.persistConfig(next)) return configRoot.lastError || "Could not persist Aurelia shell config."
        return ""
    }

    function setBarWidget(id, key, value, selector) {
        if (!configRoot.isValidPluginId(id)) return "Invalid widget id: " + id
        if (!configRoot.isSafeSettingKey(key) || ["id", "instanceId", "settings"].indexOf(String(key)) !== -1)
            return "Invalid widget setting key: " + key
        var selectorResult = configRoot.validatePlacement(selector, true)
        if (!selectorResult.ok) return selectorResult.error
        var selected = selectorResult.value
        if (configRoot.objectHas(selected, "before") || configRoot.objectHas(selected, "after"))
            return "set does not accept before or after"
        if (configRoot.objectHas(selected, "section") && configRoot.objectHas(selected, "fromSection"))
            return "set accepts only one of section or from-section"
        if (configRoot.objectHas(selected, "index") && configRoot.objectHas(selected, "fromIndex"))
            return "set accepts only one of index or from-index"
        if (configRoot.objectHas(selected, "index") && !configRoot.objectHas(selected, "section"))
            return "index requires section"
        if (configRoot.objectHas(selected, "fromIndex") && !configRoot.objectHas(selected, "fromSection"))
            return "from-index requires from-section"
        var next = configRoot.prepareMutationConfig()
        var lookup = configRoot.cloneJson(selected) || ({})
        if (configRoot.objectHas(lookup, "section")) {
            lookup.fromSection = lookup.section
            delete lookup.section
        }
        if (configRoot.objectHas(lookup, "index")) {
            lookup.fromIndex = lookup.index
            delete lookup.index
        }
        var location = configRoot.resolveBarLocation(next, id, lookup)
        if (!location.found) return location.error
        var entry = next.bar.layout[location.section][location.index]
        if (!configRoot.isPlainObject(entry)) return "widget entry must be an object"
        var copiedValue = configRoot.cloneJson(value)
        if (copiedValue === null && value !== null) return "widget setting value must be JSON"
        entry[String(key)] = copiedValue
        if (!configRoot.persistConfig(next)) return configRoot.lastError || "Could not persist Aurelia shell config."
        return ""
    }

    function inlineSettingsFromEntry(entry) {
        var result = {}
        if (!configRoot.isPlainObject(entry)) return result
        var explicit = {}
        for (var key in entry) {
            if (key !== "id" && key !== "instanceId" && key !== "settings") {
                result[key] = entry[key]
                explicit[key] = true
            }
        }
        if (configRoot.isPlainObject(entry.settings)) {
            for (var nestedKey in entry.settings) {
                if (!explicit[nestedKey]) result[nestedKey] = entry.settings[nestedKey]
            }
        }
        return result
    }

    function settingsForEntry(id, selector) {
        var selectorResult = configRoot.validateSettingsSelector(selector)
        if (!selectorResult.ok) return ({})
        var location = configRoot.findConfigEntry(configRoot.config, String(id || ""), selectorResult.value)
        if (!location.found) return ({})
        var entry = location.kind === "bar"
            ? configRoot.config.bar.layout[location.section][location.index]
            : configRoot.config.plugins[location.index]
        if (location.kind === "bar" && configRoot.barWidgetRegistry &&
            typeof configRoot.barWidgetRegistry.settingsFor === "function")
            return configRoot.barWidgetRegistry.settingsFor(String(entry.id || id || ""), entry)
        return configRoot.cloneJson(configRoot.inlineSettingsFromEntry(entry)) || ({})
    }

    function updateEntryInline(id, settings, selector) {
        var selectorResult = configRoot.validateSettingsSelector(selector)
        if (!selectorResult.ok) {
            configRoot.lastError = selectorResult.error
            return false
        }
        var settingsResult = configRoot.validateSettingsObject(settings)
        if (!settingsResult.ok) {
            configRoot.lastError = settingsResult.error
            return false
        }
        var next = configRoot.prepareMutationConfig()
        var location = configRoot.findConfigEntry(next, String(id || ""), selectorResult.value)
        if (!location.found) {
            configRoot.lastError = location.error || "could not find configured plugin " + id
            return false
        }
        var entry = location.kind === "bar"
            ? next.bar.layout[location.section][location.index]
            : next.plugins[location.index]
        if (!configRoot.isPlainObject(entry)) {
            configRoot.lastError = "configured plugin entry must be an object"
            return false
        }
        var before = configRoot.serializeConfig(next)
        var keys = Object.keys(settingsResult.value)
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++)
            entry[keys[keyIndex]] = settingsResult.value[keys[keyIndex]]
        if (before === configRoot.serializeConfig(next)) {
            configRoot.config = next
            configRoot.lastSaveOk = true
            configRoot.lastError = ""
            return false
        }
        if (!configRoot.persistConfig(next)) return false
        return true
    }

    function resetEntryInline(id, selector) {
        var selectorResult = configRoot.validateSettingsSelector(selector)
        if (!selectorResult.ok) {
            configRoot.lastError = selectorResult.error
            return false
        }
        var next = configRoot.prepareMutationConfig()
        var location = configRoot.findConfigEntry(next, String(id || ""), selectorResult.value)
        if (!location.found) {
            configRoot.lastError = location.error || "could not find configured plugin " + id
            return false
        }
        var entries = location.kind === "bar" ? next.bar.layout[location.section] : next.plugins
        var entry = entries[location.index]
        if (!configRoot.isPlainObject(entry)) {
            configRoot.lastError = "configured plugin entry must be an object"
            return false
        }
        var resetEntry = {}
        if (typeof entry.instanceId === "string" && configRoot.isValidPluginId(entry.instanceId))
            resetEntry.instanceId = entry.instanceId
        resetEntry.id = entry.id
        var before = configRoot.serializeConfig(next)
        entries[location.index] = resetEntry
        if (before === configRoot.serializeConfig(next)) {
            configRoot.config = next
            configRoot.lastSaveOk = true
            configRoot.lastError = ""
            return false
        }
        if (!configRoot.persistConfig(next)) return false
        return true
    }

    function isPluginEnabled(id, firstParty) {
        if (!isValidPluginId(id)) return false
        if (contains(configRoot.config.disabledPlugins, id)) return false
        if (firstParty) return true
        if (containsPluginEntry(configRoot.config.plugins, id)) return true
        return configRoot.findBarLocation(configRoot.config, id, "").found
    }

    Component.onCompleted: configRoot.reload()
}
