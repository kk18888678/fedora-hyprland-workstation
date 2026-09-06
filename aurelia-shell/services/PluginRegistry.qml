import QtQuick
import Quickshell
import Quickshell.Io

// Aurelia's manifest registry follows the Omarchy contract while keeping the
// discovery surface deliberately small. It scans only plugin directories,
// validates metadata before a Loader can see it, and never executes plugin
// code during discovery. Rescans are explicit; an unbounded recursive watcher
// is not part of the shell's idle path.
QtObject {
    id: registry

    readonly property string packageRoot: pathFromUrl(Qt.resolvedUrl(".."))
    property string firstPartyDir: pathFromUrl(Qt.resolvedUrl("../plugins"))
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

    signal pluginsChanged()
    signal scanFinished()
    signal pluginRejected(string sourcePath, string reason)

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

    function isSafeEntryPoint(value) {
        return typeof value === "string" && value.length > 0 && value.charAt(0) !== "/" && value.indexOf("..") === -1 && value.indexOf("\\") === -1 && value.indexOf(":") === -1
    }

    function hasKind(manifest, kind) {
        return Array.isArray(manifest.kinds) && manifest.kinds.indexOf(kind) !== -1
    }

    function validateManifest(manifest, sourcePath, firstParty) {
        if (!isPlainObject(manifest)) return null
        if (manifest.schemaVersion !== 1) return null
        if (typeof manifest.id !== "string" || !isValidPluginId(manifest.id)) return null
        if (typeof manifest.name !== "string" || manifest.name.trim() === "") return null
        if (typeof manifest.version !== "string" || manifest.version.trim() === "") return null
        if (!Array.isArray(manifest.kinds) || manifest.kinds.length === 0) return null
        if (!isPlainObject(manifest.entryPoints)) return null
        if (firstParty && manifest.id.indexOf("aurelia.") !== 0) return null
        if (!firstParty && manifest.id.indexOf("aurelia.") === 0) return null

        for (var entryName in manifest.entryPoints) {
            if (!isSafeEntryPoint(manifest.entryPoints[entryName])) return null
        }

        var seenKinds = {}
        for (var i = 0; i < manifest.kinds.length; i++) {
            var kind = manifest.kinds[i]
            if (typeof kind !== "string" || supportedKinds.indexOf(kind) === -1 || seenKinds[kind]) return null
            seenKinds[kind] = true
            if (!isSafeEntryPoint(manifest.entryPoints[kind])) return null
        }

        if (manifest.keepLoaded !== undefined && typeof manifest.keepLoaded !== "boolean") return null
        manifest.__sourceDir = sourcePath
        manifest.__isFirstParty = firstParty
        return manifest
    }

    function primaryKind(id) {
        var manifest = installedPlugins[id]
        if (!manifest) return ""
        for (var i = 0; i < loadKindOrder.length; i++) {
            if (hasKind(manifest, loadKindOrder[i])) return loadKindOrder[i]
        }
        return ""
    }

    function entryPointUrl(id, kind) {
        var manifest = installedPlugins[id]
        if (!manifest || !isSafeEntryPoint(manifest.entryPoints[kind])) return ""
        var sourceDir = String(manifest.__sourceDir || "")
        if (sourceDir === "" || sourceDir.charAt(0) !== "/") return ""
        return fileUrl(sourceDir.replace(/\/$/, "") + "/" + manifest.entryPoints[kind])
    }

    function isKnown(id) {
        return !!installedPlugins[id]
    }

    function isEnabled(id) {
        var manifest = installedPlugins[id]
        if (!manifest || !shellConfig) return false
        return shellConfig.isPluginEnabled(id, manifest.__isFirstParty === true)
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
                kinds: manifest.kinds.slice(),
                firstParty: manifest.__isFirstParty === true,
                enabled: isEnabled(ids[i]),
                keepLoaded: manifest.keepLoaded === true
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
        "    local valid=1",
        "    while IFS= read -r kind; do",
        "      local entry_point",
        "      entry_point=\"$(jq -r --arg kind \"$kind\" '.entryPoints[$kind] // empty' \"$manifest_path\")\"",
        "      [[ -n \"$entry_point\" && \"$entry_point\" != /* && \"$entry_point\" != *..* && \"$entry_point\" != *\\\\* && \"$entry_point\" != *:* && -f \"$plugin_dir/$entry_point\" && ! -L \"$plugin_dir/$entry_point\" ]] || valid=0",
        "    done < <(jq -r '.kinds[]? // empty' \"$manifest_path\")",
        "    [[ \"$valid\" -eq 1 ]] || continue",
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
        command: ["bash", "-c", registry.scanScript, "aurelia-plugin-scan", registry.firstPartyDir, registry.userPluginsDir]

        stdout: StdioCollector { id: scanOutput }
        stderr: StdioCollector { id: scanError }

        onExited: function(code) {
            if (code !== 0) {
                registry.scanning = false
                registry.lastError = scanError.text || "Aurelia plugin scan failed."
                return
            }
            registry.parseScanOutput(scanOutput.text)
        }
    }

    function scan() {
        if (scanning || scanProcess.running) return false
        scanning = true
        lastError = ""
        scanProcess.command = ["bash", "-c", scanScript, "aurelia-plugin-scan", firstPartyDir, userPluginsDir]
        scanProcess.running = true
        return true
    }

    Component.onCompleted: scan()
}
