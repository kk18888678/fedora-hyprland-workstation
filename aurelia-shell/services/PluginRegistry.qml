import QtQuick
import Quickshell
import Quickshell.Io

// Aurelia's manifest registry follows the Omarchy contract while keeping the
// discovery surface deliberately small. It scans only plugin directories,
// validates metadata before a Loader can see it, and never executes plugin
// code during discovery. In development mode it also follows Omarchy's
// bounded plugin-only watcher contract: a changed local plugin requests a
// debounced host reload, while the shell's own core files remain restart-only.
QtObject {
    id: registry

    readonly property string configuredShellRoot: {
        var value = Quickshell.env("AURELIA_SHELL_ROOT") || ""
        return value.charAt(0) === "/" && value !== "/" ? value.replace(/\/$/, "") : ""
    }
    readonly property string packageRoot: configuredShellRoot !== ""
        ? configuredShellRoot
        : pathFromUrl(Qt.resolvedUrl(".."))
    readonly property string manifestValidatorPath: packageRoot + "/bin/aurelia-plugin"
    property string firstPartyDir: configuredShellRoot !== ""
        ? configuredShellRoot + "/plugins"
        : pathFromUrl(Qt.resolvedUrl("../plugins"))
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHomeOverride: Quickshell.env("XDG_CONFIG_HOME") || ""
    readonly property string configHome: configHomeOverride.charAt(0) === "/" ? configHomeOverride : (home + "/.config")
    readonly property string userPluginsDir: configHome + "/aurelia/plugins"

    property var shellConfig: null
    property var installedPlugins: ({})
    property int registryRevision: 0
    property bool scanning: false
    property string lastError: ""
    property int rejectedCount: 0
    // Runtime failures are deliberately ephemeral. They keep a bad entry
    // point out of the current generation without changing shell.json,
    // enabled state, or any user-owned data.
    property var runtimeFailures: ({})
    property int runtimeFailureRevision: 0
    property bool localPluginWatcherUnavailable: false
    readonly property bool hotReloadEnabled: Quickshell.env("AURELIA_HOT_RELOAD") === "1"
        || Quickshell.env("AURELIA_DEVELOPMENT_MODE") === "1"

    signal pluginsChanged()
    signal scanFinished()
    signal pluginRejected(string sourcePath, string reason)
    signal pluginFailureRecorded(string pluginId, string kind, string phase, string sourcePath, string entryPoint, string detail)
    signal localPluginChanged(string pluginId)

    property Connections shellConfigConnection: Connections {
        target: registry.shellConfig
        function onConfigChanged() {
            registry.registryRevision++
            registry.pluginsChanged()
        }
    }

    readonly property var supportedKinds: ["bar-widget", "bar", "panel", "overlay", "menu", "service"]
    readonly property var loadKindOrder: ["panel", "overlay", "menu", "bar", "bar-widget", "service"]

    function pathFromUrl(value) {
        var text = String(value || "")
        if (text.indexOf("file://") === 0) {
            return decodeURIComponent(text.substring(7))
        }
        return text
    }

    function fileUrl(value) {
        var parts = String(value || "").split("/")
        for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
        return "file://" + parts.join("/")
    }

    function isPlainObject(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value)
    }

    function isValidPluginId(value) {
        return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value) && value.indexOf("..") === -1
    }

    function localPluginIdForPath(filePath) {
        var path = String(filePath || "").trim()
        var roots = [firstPartyDir, userPluginsDir]
        for (var i = 0; i < roots.length; i++) {
            var base = String(roots[i] || "").replace(/\/$/, "") + "/"
            if (base === "/" || path.indexOf(base) !== 0) continue

            var relative = path.slice(base.length)
            // Hidden entries and checkout metadata are not plugin changes.
            if (!relative || relative.indexOf(".") === 0 || relative.indexOf("/.git/") !== -1 || relative.endsWith("/.git")) return ""
            if (!/\.(qml|js|json|jsonc|lua|conf)$/.test(relative)) return ""

            var slash = relative.indexOf("/")
            var pluginId = slash === -1 ? relative : relative.slice(0, slash)
            return isValidPluginId(pluginId) ? pluginId : ""
        }
        return ""
    }

    function isValidIconName(value) {
        return typeof value === "string" && value.length > 0 && value.length <= 128 && /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value)
    }

    function isSafeEntryPoint(value) {
        return typeof value === "string" && value.length > 0 && value.charAt(0) !== "/" &&
            value.indexOf("..") === -1 && value.indexOf("\\") === -1 && value.indexOf(":") === -1 &&
            !/[\x00-\x1f\x7f]/.test(value)
    }

    function hasField(object, key) {
        return isPlainObject(object) && Object.keys(object).indexOf(String(key)) !== -1
    }

    function isNonEmptyText(value) {
        return typeof value === "string" && value.trim() !== ""
    }

    function isSafeSettingKey(value) {
        return typeof value === "string" && /^[A-Za-z][A-Za-z0-9_.-]*$/.test(value)
    }

    function entryPointKeyForKind(kind, manifest) {
        if (kind !== "bar-widget") return kind
        return hasField(manifest.entryPoints, "barWidget") ? "barWidget" : "bar-widget"
    }

    function entryPointForKind(manifest, kind) {
        if (!manifest || !isPlainObject(manifest.entryPoints)) return ""
        var key = entryPointKeyForKind(kind, manifest)
        return manifest.entryPoints[key]
    }

    function validateSchemaOption(option) {
        if (typeof option === "string") return isNonEmptyText(option)
        if (!isPlainObject(option)) return false
        var allowed = ["value", "label", "description"]
        var keys = Object.keys(option)
        for (var i = 0; i < keys.length; i++) if (allowed.indexOf(keys[i]) === -1) return false
        if (!isNonEmptyText(option.value) || !isNonEmptyText(option.label)) return false
        return !hasField(option, "description") || isNonEmptyText(option.description)
    }

    function validateSchemaItem(item) {
        if (!isPlainObject(item)) return false
        var allowed = ["key", "type", "label", "description", "min", "max", "step",
            "defaultValue", "options", "noSelectionText", "placeholderText", "emptyText"]
        var keys = Object.keys(item)
        for (var i = 0; i < keys.length; i++) if (allowed.indexOf(keys[i]) === -1) return false
        if (!isSafeSettingKey(item.key) || !isNonEmptyText(item.label)) return false
        var types = ["string", "integer", "number", "boolean", "enum", "path", "multiselect"]
        if (typeof item.type !== "string" || types.indexOf(item.type) === -1) return false
        if (hasField(item, "description") && !isNonEmptyText(item.description)) return false
        if (hasField(item, "min") && typeof item.min !== "number") return false
        if (hasField(item, "max") && typeof item.max !== "number") return false
        if (hasField(item, "step") && typeof item.step !== "number") return false
        if (hasField(item, "options")) {
            if (!Array.isArray(item.options)) return false
            for (var optionIndex = 0; optionIndex < item.options.length; optionIndex++)
                if (!validateSchemaOption(item.options[optionIndex])) return false
        }
        if (hasField(item, "noSelectionText") && !isNonEmptyText(item.noSelectionText)) return false
        if (hasField(item, "placeholderText") && !isNonEmptyText(item.placeholderText)) return false
        if (hasField(item, "emptyText") && !isNonEmptyText(item.emptyText)) return false
        return true
    }

    function validateBarWidgetMetadata(metadata) {
        if (!isPlainObject(metadata)) return false
        var allowed = ["displayName", "description", "category", "aliases",
            "allowMultiple", "defaultSection", "defaults", "settingsForm", "schema"]
        var keys = Object.keys(metadata)
        for (var i = 0; i < keys.length; i++) if (allowed.indexOf(keys[i]) === -1) return false
        if (!isNonEmptyText(metadata.displayName) || !isNonEmptyText(metadata.description) ||
            !isNonEmptyText(metadata.category) || typeof metadata.allowMultiple !== "boolean") return false
        if (hasField(metadata, "aliases")) {
            if (!Array.isArray(metadata.aliases)) return false
            for (var aliasIndex = 0; aliasIndex < metadata.aliases.length; aliasIndex++)
                if (!isNonEmptyText(metadata.aliases[aliasIndex])) return false
        }
        if (hasField(metadata, "defaultSection") &&
            ["left", "center", "right"].indexOf(metadata.defaultSection) === -1) return false
        if (hasField(metadata, "defaults") && !isPlainObject(metadata.defaults)) return false
        if (hasField(metadata, "settingsForm") &&
            (typeof metadata.settingsForm !== "string" ||
             (metadata.settingsForm !== "" && !isSafeSettingKey(metadata.settingsForm)))) return false
        if (hasField(metadata, "schema")) {
            if (!Array.isArray(metadata.schema)) return false
            for (var schemaIndex = 0; schemaIndex < metadata.schema.length; schemaIndex++)
                if (!validateSchemaItem(metadata.schema[schemaIndex])) return false
        }
        return true
    }

    function validateAureliaMetadata(metadata, firstParty) {
        if (!isPlainObject(metadata)) return false
        var allowed = ["icon", "clonePaths", "capabilities", "compatibility"]
        var keys = Object.keys(metadata)
        for (var i = 0; i < keys.length; i++) if (allowed.indexOf(keys[i]) === -1) return false
        if (hasField(metadata, "icon") && !isValidIconName(metadata.icon)) return false
        if (hasField(metadata, "clonePaths")) {
            if (!Array.isArray(metadata.clonePaths)) return false
            var clonePairs = []
            for (var cloneIndex = 0; cloneIndex < metadata.clonePaths.length; cloneIndex++) {
                var clonePath = metadata.clonePaths[cloneIndex]
                if (!isPlainObject(clonePath) || Object.keys(clonePath).some(function(key) {
                    return ["source", "target"].indexOf(key) === -1
                }) || !isSafeEntryPoint(clonePath.source) || !isSafeEntryPoint(clonePath.target)) return false
                var pair = clonePath.source + "\\u0000" + clonePath.target
                if (clonePairs.indexOf(pair) !== -1) return false
                clonePairs.push(pair)
            }
        }
        if (hasField(metadata, "capabilities")) {
            if (firstParty !== true || !Array.isArray(metadata.capabilities)) return false
            for (var capabilityIndex = 0; capabilityIndex < metadata.capabilities.length; capabilityIndex++)
                if (!isSafeSettingKey(metadata.capabilities[capabilityIndex])) return false
        }
        if (hasField(metadata, "compatibility")) {
            if (!isPlainObject(metadata.compatibility) ||
                Object.keys(metadata.compatibility).length !== 1 ||
                !isNonEmptyText(metadata.compatibility.hostApi)) return false
        }
        return true
    }

    function cloneManifest(manifest) {
        try {
            return JSON.parse(JSON.stringify(manifest))
        } catch (e) {
            return null
        }
    }

    function runtimeFailureKey(id, kind) {
        return String(id || "") + "::" + String(kind || "")
    }

    function boundedFailureDetail(value) {
        var detail = ""
        try {
            if (value && value.message !== undefined) detail = String(value.message)
            else detail = String(value || "")
        } catch (e) {
            detail = "plugin failure detail unavailable"
        }
        detail = detail.replace(/\s+/g, " ").trim()
        if (detail.length > 512) detail = detail.substring(0, 512) + "..."
        return detail || "plugin failure"
    }

    function failureCopy(failure) {
        if (!failure) return null
        var result = {}
        for (var property in failure) result[property] = failure[property]
        result.active = failure.quarantined === true && Number(failure.generation) === registry.registryRevision
        return result
    }

    function runtimeFailureFor(id, kind) {
        var key = registry.runtimeFailureKey(id, kind)
        return failureCopy(registry.runtimeFailures[key])
    }

    function runtimeFailuresFor(id) {
        var prefix = String(id || "") + "::"
        var result = []
        var keys = Object.keys(registry.runtimeFailures || {})
        for (var i = 0; i < keys.length; i++) {
            if (keys[i].indexOf(prefix) !== 0) continue
            var failure = failureCopy(registry.runtimeFailures[keys[i]])
            if (failure) result.push(failure)
        }
        result.sort(function(left, right) {
            return String(left.kind || "").localeCompare(String(right.kind || ""))
        })
        return result
    }

    function hasActiveRuntimeFailure(id, kind) {
        // Read the revision so QML bindings depending on this method are
        // reevaluated when a loader is quarantined or a failure is cleared.
        var failureRevision = registry.runtimeFailureRevision
        var pluginId = String(id || "")
        if (kind !== undefined && kind !== null && String(kind) !== "") {
            var exact = registry.runtimeFailures[registry.runtimeFailureKey(pluginId, kind)]
            return !!exact && exact.quarantined === true && Number(exact.generation) === registry.registryRevision
        }
        var failures = registry.runtimeFailuresFor(pluginId)
        for (var i = 0; i < failures.length; i++) {
            if (failures[i].active === true) return true
        }
        return false
    }

    function recordRuntimeFailure(id, kind, phase, sourcePath, entryPoint, detail) {
        var pluginId = String(id || "").trim()
        var pluginKind = String(kind || "").trim()
        if (!registry.isValidPluginId(pluginId) || !pluginKind || !/^[A-Za-z0-9-]+$/.test(pluginKind)) return false

        var key = registry.runtimeFailureKey(pluginId, pluginKind)
        var next = {}
        var existing = registry.runtimeFailures[key]
        for (var existingKey in (registry.runtimeFailures || {})) next[existingKey] = registry.runtimeFailures[existingKey]
        var attempts = existing && Number(existing.attempts) > 0 ? Number(existing.attempts) + 1 : 1
        var boundedSource = String(sourcePath || "")
        var boundedEntry = String(entryPoint || "")
        if (boundedSource.length > 1024) boundedSource = boundedSource.substring(0, 1024) + "..."
        if (boundedEntry.length > 256) boundedEntry = boundedEntry.substring(0, 256) + "..."
        next[key] = {
            id: pluginId,
            kind: pluginKind,
            phase: String(phase || "runtime"),
            sourcePath: boundedSource,
            entryPoint: boundedEntry,
            detail: registry.boundedFailureDetail(detail),
            timestamp: Date.now(),
            generation: registry.registryRevision,
            attempts: attempts,
            quarantined: true,
            retryState: "requires-explicit-reload"
        }
        registry.runtimeFailures = next
        registry.runtimeFailureRevision++
        console.warn("[PLUGIN] aurelia.plugin.failure id=" + pluginId +
            " kind=" + pluginKind + " phase=" + String(phase || "runtime") +
            " state=quarantined detail=" + next[key].detail)
        registry.pluginFailureRecorded(pluginId, pluginKind, String(phase || "runtime"),
            boundedSource, boundedEntry, next[key].detail)
        return true
    }

    function clearRuntimeFailure(id, kind) {
        var pluginId = String(id || "").trim()
        if (!pluginId) return false
        var next = {}
        var changed = false
        var prefix = pluginId + "::"
        for (var key in (registry.runtimeFailures || {})) {
            var matches = key.indexOf(prefix) === 0 &&
                (kind === undefined || kind === null || String(kind) === "" || key === registry.runtimeFailureKey(pluginId, kind))
            if (matches) changed = true
            else next[key] = registry.runtimeFailures[key]
        }
        if (!changed) return false
        registry.runtimeFailures = next
        registry.runtimeFailureRevision++
        return true
    }

    function hasKind(manifest, kind) {
        return Array.isArray(manifest.kinds) && manifest.kinds.indexOf(kind) !== -1
    }

    function validateManifest(manifest, sourcePath, firstParty) {
        if (!isPlainObject(manifest)) return null
        var allowed = ["schemaVersion", "id", "name", "version", "author", "license",
            "description", "icon", "kinds", "entryPoints", "keepLoaded", "activation",
            "barWidget", "aurelia"]
        var manifestKeys = Object.keys(manifest)
        for (var keyIndex = 0; keyIndex < manifestKeys.length; keyIndex++)
            if (allowed.indexOf(manifestKeys[keyIndex]) === -1) return null
        if (manifest.schemaVersion !== 1 || !isValidPluginId(manifest.id) ||
            !isNonEmptyText(manifest.name) || !isNonEmptyText(manifest.version) ||
            !isNonEmptyText(manifest.description)) return null
        if (typeof sourcePath !== "string" || sourcePath.charAt(0) !== "/") return null
        if (firstParty === true && manifest.id.indexOf("aurelia.") !== 0) return null
        if (firstParty !== true && manifest.id.indexOf("aurelia.") === 0) return null
        if (hasField(manifest, "author") && !isNonEmptyText(manifest.author)) return null
        if (hasField(manifest, "license") && !isNonEmptyText(manifest.license)) return null
        if (hasField(manifest, "icon") && !isValidIconName(manifest.icon)) return null
        if (hasField(manifest, "keepLoaded") && typeof manifest.keepLoaded !== "boolean") return null
        if (hasField(manifest, "activation") && manifest.activation !== "on-demand") return null
        if (hasField(manifest, "aurelia") && !validateAureliaMetadata(manifest.aurelia, firstParty)) return null
        if (hasField(manifest, "icon") && hasField(manifest, "aurelia") &&
            hasField(manifest.aurelia, "icon")) return null
        if (!Array.isArray(manifest.kinds) || manifest.kinds.length === 0 ||
            !isPlainObject(manifest.entryPoints) || Object.keys(manifest.entryPoints).length === 0) return null

        var seenKinds = {}
        var expectedEntryKeys = {}
        for (var i = 0; i < manifest.kinds.length; i++) {
            var kind = manifest.kinds[i]
            if (typeof kind !== "string" || supportedKinds.indexOf(kind) === -1 || seenKinds[kind]) return null
            seenKinds[kind] = true
            var entryKey = entryPointKeyForKind(kind, manifest)
            expectedEntryKeys[entryKey] = true
            if (!isSafeEntryPoint(manifest.entryPoints[entryKey])) return null
        }
        if (hasField(manifest.entryPoints, "barWidget") && hasField(manifest.entryPoints, "bar-widget")) return null
        if (hasField(manifest.entryPoints, "barWidget") &&
            (!hasKind(manifest, "bar-widget") || !hasField(manifest, "barWidget") ||
             !validateBarWidgetMetadata(manifest.barWidget))) return null
        if (hasField(manifest, "barWidget") &&
            (!hasKind(manifest, "bar-widget") || !validateBarWidgetMetadata(manifest.barWidget))) return null
        var entryKeys = Object.keys(manifest.entryPoints)
        for (var entryIndex = 0; entryIndex < entryKeys.length; entryIndex++)
            if (!expectedEntryKeys[entryKeys[entryIndex]]) return null

        var copy = registry.cloneManifest(manifest)
        if (!copy) return null
        copy.__sourceDir = sourcePath
        copy.__isFirstParty = firstParty === true
        return copy
    }

    function primaryKind(id) {
        var manifest = installedPlugins[id]
        if (!manifest) return ""
        // A service is the resident owner for a multi-kind plugin. The bar
        // host loads its separate bar-widget entry point independently; using
        // the visual entry point here would silently skip the daemon.
        if (hasKind(manifest, "service")) return "service"
        for (var i = 0; i < loadKindOrder.length; i++) {
            if (hasKind(manifest, loadKindOrder[i])) return loadKindOrder[i]
        }
        return ""
    }

    function entryPointUrl(id, kind) {
        var manifest = installedPlugins[id]
        var entryPoint = entryPointForKind(manifest, kind)
        if (!manifest || !isSafeEntryPoint(entryPoint)) return ""
        var sourceDir = String(manifest.__sourceDir || "")
        if (sourceDir === "" || sourceDir.charAt(0) !== "/") return ""
        return fileUrl(sourceDir.replace(/\/$/, "") + "/" + entryPoint)
    }

    function isKnown(id) {
        return !!installedPlugins[id]
    }

    function isEnabled(id) {
        var manifest = installedPlugins[id]
        if (!manifest || !shellConfig) return false
        return shellConfig.isPluginEnabled(id, manifest.__isFirstParty === true)
    }

    function iconForManifest(manifest) {
        if (manifest && isPlainObject(manifest.aurelia) &&
            isValidIconName(manifest.aurelia.icon)) return manifest.aurelia.icon
        return manifest && isValidIconName(manifest.icon) ? manifest.icon : ""
    }

    readonly property var pluginIds: {
        var revision = registryRevision
        var ids = Object.keys(installedPlugins)
        ids.sort()
        return ids
    }

    readonly property var enabledPluginIds: {
        var revision = registryRevision
        var result = []
        var ids = Object.keys(installedPlugins).sort()
        for (var i = 0; i < ids.length; i++) {
            if (isEnabled(ids[i])) result.push(ids[i])
        }
        return result
    }

    function pluginSummaries() {
        var result = []
        var ids = Object.keys(installedPlugins)
        ids.sort(function(left, right) {
            var leftName = String(installedPlugins[left].name || left).toLowerCase()
            var rightName = String(installedPlugins[right].name || right).toLowerCase()
            return leftName === rightName ? left.localeCompare(right) : leftName.localeCompare(rightName)
        })
        for (var i = 0; i < ids.length; i++) {
            var manifest = installedPlugins[ids[i]]
            result.push({
                id: ids[i],
                name: manifest.name,
                version: manifest.version,
                description: manifest.description || "",
                icon: iconForManifest(manifest),
                kinds: manifest.kinds.slice(),
                firstParty: manifest.__isFirstParty === true,
                enabled: isEnabled(ids[i]),
                keepLoaded: manifest.keepLoaded === true,
                failures: runtimeFailuresFor(ids[i])
            })
        }
        return result
    }

    function setPluginEnabled(id, enabled) {
        var manifest = installedPlugins[id]
        if (!manifest || !shellConfig) {
            lastError = "Unknown plugin: " + id
            return false
        }
        if (!shellConfig.setPluginEnabled(id, manifest.__isFirstParty === true, enabled)) {
            lastError = shellConfig.lastError || ("Could not persist plugin state: " + id)
            return false
        }
        lastError = ""
        registryRevision++
        pluginsChanged()
        return true
    }

    function parseScanOutput(text) {
        var lines = String(text || "").split("\n")
        var discovered = {}
        registry.rejectedCount = 0
        var currentSource = ""
        var currentFirstParty = false
        var currentJson = []

        function flush() {
            if (currentSource === "") return
            var raw = currentJson.join("\n").trim()
            try {
                var parsed = JSON.parse(raw)
                var validated = registry.validateManifest(parsed, currentSource, currentFirstParty)
                if (!validated) {
                    registry.rejectedCount++
                    console.warn("[PLUGIN] aurelia.plugin.rejected path=" + currentSource + " reason=manifest_validation")
                    registry.pluginRejected(currentSource, "manifest validation failed")
                } else if (discovered[validated.id]) {
                    registry.rejectedCount++
                    console.warn("[PLUGIN] aurelia.plugin.rejected path=" + currentSource + " reason=duplicate_id")
                    registry.pluginRejected(currentSource, "plugin id is duplicated")
                } else {
                    discovered[validated.id] = validated
                }
            } catch (e) {
                registry.rejectedCount++
                console.warn("[PLUGIN] aurelia.plugin.rejected path=" + currentSource + " reason=invalid_json")
                registry.pluginRejected(currentSource, "manifest is not valid JSON")
            }
            currentSource = ""
            currentJson = []
        }

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            var start = line.match(/^===([a-z-]+)::(.+)===$/)
            if (start) {
                flush()
                currentFirstParty = start[1] === "firstparty"
                currentSource = start[2].replace(/\/$/, "")
                currentJson = []
                continue
            }
            if (line === "===AURELIA_PLUGIN_END===") {
                flush()
                continue
            }
            if (currentSource !== "") currentJson.push(line)
        }
        flush()

        installedPlugins = discovered
        lastError = ""
        registryRevision++
        scanning = false
        pluginsChanged()
        scanFinished()
    }

    readonly property string scanScript: [
        "set -Eeuo pipefail",
        "command -v jq >/dev/null 2>&1 || exit 1",
        "validator=\"$3\"",
        "[[ -x \"$validator\" ]] || exit 1",
        "first_party_root=\"$(readlink -f -- \"$1\" 2>/dev/null || true)\"",
        "[[ -n \"$first_party_root\" ]] || exit 1",
        "scan_tree() {",
        "  local source_kind=\"$1\"",
        "  local root=\"$2\"",
        "  local max_depth=\"$3\"",
        "  [[ -d \"$root\" ]] || return 0",
        "  if [[ \"$source_kind\" == \"thirdparty\" ]]; then",
        "    local root_real=\"$(readlink -f -- \"$root\" 2>/dev/null || true)\"",
        "    [[ -n \"$root_real\" ]] || return 0",
        "    if [[ \"$root_real\" == \"$first_party_root\" || \"$root_real\" == \"$first_party_root/\"* || \"$first_party_root\" == \"$root_real/\"* ]]; then",
        "      return 0",
        "    fi",
        "  fi",
        "  while IFS= read -r manifest_path; do",
        "    local plugin_dir=\"${manifest_path%/manifest.json}\"",
        "    [[ -L \"$plugin_dir\" ]] && continue",
        "    find -P \"$plugin_dir\" -type l -print -quit | grep -q . && continue",
        "    jq -e '.schemaVersion == 1 and (.id | type == \"string\") and (.name | type == \"string\") and (.version | type == \"string\") and (.kinds | type == \"array\") and (.entryPoints | type == \"object\")' \"$manifest_path\" >/dev/null 2>&1 || continue",
        "    if [[ \"$source_kind\" == \"firstparty\" ]]; then",
        "      \"$validator\" validate --first-party \"$plugin_dir\" >/dev/null 2>&1 || continue",
        "    else",
        "      \"$validator\" validate \"$plugin_dir\" >/dev/null 2>&1 || continue",
        "    fi",
        "    printf '===%s::%s===\\n' \"$source_kind\" \"$plugin_dir\"",
        "    cat \"$manifest_path\"",
        "    printf '\\n===AURELIA_PLUGIN_END===\\n'",
        "  done < <(find -P \"$root\" -mindepth 2 -maxdepth \"$max_depth\" -type f -name manifest.json -print | LC_ALL=C sort)",
        "}",
        "scan_tree firstparty \"$1\" 3",
        "scan_tree thirdparty \"$2\" 2"
    ].join("\n")

    property Process scanProcess: Process {
        id: scanProcess
        command: ["bash", "-c", registry.scanScript, "aurelia-plugin-scan", registry.firstPartyDir, registry.userPluginsDir, registry.manifestValidatorPath]

        stdout: StdioCollector { id: scanOutput }
        stderr: StdioCollector { id: scanError }

        onExited: function(code) {
            if (code !== 0) {
                registry.scanning = false
                registry.lastError = scanError.text || "Aurelia plugin scan failed."
                registry.scanFinished()
                return
            }
            registry.parseScanOutput(scanOutput.text)
        }
    }

    property Process ensureUserPluginsDir: Process {
        id: ensureUserPluginsDir
        command: ["bash", "-c", "mkdir -p -- \"$1\"", "aurelia-plugin-init", registry.userPluginsDir]

        onExited: function(code) {
            if (code !== 0) {
                registry.lastError = "Could not initialize the Aurelia plugin directory."
                registry.scan()
                return
            }
            if (registry.hotReloadEnabled && !registry.localPluginWatcherUnavailable) registry.localPluginWatcher.running = true
            registry.scan()
        }
    }

    property Process localPluginWatcher: Process {
        id: localPluginWatcher
        command: [
            "inotifywait",
            "-m",
            "-r",
            "-q",
            "-e",
            "close_write,create,delete,move",
            "--format",
            "%w%f",
            registry.firstPartyDir,
            registry.userPluginsDir
        ]

        stdout: SplitParser {
            onRead: function(path) {
                var pluginId = registry.localPluginIdForPath(path)
                if (pluginId) registry.localPluginChanged(pluginId)
            }
        }

        onExited: function(code) {
            if (code === 127) {
                registry.localPluginWatcherUnavailable = true
                registry.lastError = "Automatic Aurelia plugin reload is unavailable: inotify-tools is not installed."
                return
            }
            if (registry.hotReloadEnabled && !registry.localPluginWatcherUnavailable) localPluginWatcherRestart.restart()
        }
    }

    property Timer localPluginWatcherRestart: Timer {
        id: localPluginWatcherRestart
        interval: 1000
        repeat: false
        onTriggered: {
            if (registry.hotReloadEnabled && !registry.localPluginWatcherUnavailable) registry.localPluginWatcher.running = true
        }
    }

    function scan() {
        if (scanning || scanProcess.running) return false
        scanning = true
        lastError = ""
        scanProcess.command = ["bash", "-c", scanScript, "aurelia-plugin-scan", firstPartyDir, userPluginsDir, manifestValidatorPath]
        scanProcess.running = true
        return true
    }

    Component.onCompleted: ensureUserPluginsDir.running = true
}
