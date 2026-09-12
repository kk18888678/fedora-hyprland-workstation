import QtQuick
import Quickshell
import Quickshell.Io

// Declarative Command Center module catalog.
//
// Module metadata is separate from the presentation and provider code. Core
// modules have a safe built-in fallback; user enablement is stored in the
// plugin-owned command-center.json and never changes the shell host.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHomeOverride: Quickshell.env("XDG_CONFIG_HOME") || ""
    readonly property string configHome: configHomeOverride.charAt(0) === "/" ? configHomeOverride : (home + "/.config")
    readonly property string defaultModulesPath: pathFromUrl(Qt.resolvedUrl("../modules.json"))
    readonly property string userModulesPath: configHome + "/aurelia/command-center.json"

    readonly property var builtinModules: [
        { id: "apps", name: "Applications", icon: "applications-system", description: "Launch installed desktop applications.", enabled: true, implemented: true, order: 10 },
        { id: "files", name: "Files", icon: "system-file-manager", description: "Search files and folders in your home directory.", enabled: true, implemented: true, order: 20 },
        { id: "actions", name: "Actions", icon: "system-run", description: "Run configured Aurelia and workstation actions.", enabled: true, implemented: true, order: 30 },
        { id: "calculator", name: "Calculator", icon: "accessories-calculator", description: "Evaluate a safe arithmetic expression.", enabled: true, implemented: true, order: 40 },
        { id: "package-manager", name: "Package Manager", icon: "system-software-install", description: "Search Fedora, Flatpak, and Aurelia sources, install, adopt, and track packages.", enabled: true, implemented: true, order: 50 },
        { id: "updates", name: "Updates", icon: "system-software-update", description: "Open the Fedora and Flatpak update workflow.", enabled: true, implemented: true, order: 60 },
        { id: "weather", name: "Weather", icon: "weather-clear", description: "Current weather and forecast.", enabled: false, implemented: false, order: 70 },
        { id: "currency", name: "Currency", icon: "wallet", description: "Currency conversion and rates.", enabled: false, implemented: false, order: 80 },
        { id: "metals", name: "Gold & Metals", icon: "emblem-money", description: "Gold and precious-metal prices.", enabled: false, implemented: false, order: 90 },
        { id: "stocks", name: "Stocks", icon: "view-statistics", description: "Market prices and watchlists.", enabled: false, implemented: false, order: 100 },
        { id: "aurelia-shell", name: "Aurelia Shell", icon: "utilities-terminal", description: "Reload plugins or restart the resident shell while developing.", enabled: true, implemented: true, order: 110 },
        { id: "about", name: "About", icon: "help-about", description: "View Aurelia system details and graphical branding.", enabled: true, implemented: true, order: 120 },
        { id: "plugins", name: "Plugins", icon: "system-run", description: "Enable, disable, clone, update, or remove Aurelia plugins.", enabled: true, implemented: true, order: 130 }
    ]

    property var modules: builtinModules
    property var userOverrides: ({})
    property string lastError: ""
    property bool lastSaveOk: false
    readonly property var supportedProviders: ["apps", "files", "actions", "calculator",
        "package-manager", "updates", "aurelia-shell", "about", "plugins"]

    function pathFromUrl(value) {
        var text = String(value || "")
        return text.indexOf("file://") === 0 ? decodeURIComponent(text.substring(7)) : text
    }

    function parseModules(raw) {
        try {
            var parsed = JSON.parse(String(raw || ""))
            if (Array.isArray(parsed)) return parsed
            if (parsed && Array.isArray(parsed.modules)) return parsed.modules
        } catch (error) {
            root.lastError = "Command Center module catalog is invalid; using built-in modules."
        }
        return root.builtinModules
    }

    function loadDefaults(raw) {
        var parsed = root.parseModules(raw)
        var valid = []
        for (var i = 0; i < parsed.length; i++) {
            var module = parsed[i]
            if (!module || typeof module.id !== "string" || !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(module.id)) continue
            if (typeof module.name !== "string" || module.name.trim() === "") continue
            var provider = module.provider === undefined ? module.id : String(module.provider)
            if (root.supportedProviders.indexOf(provider) === -1) continue
            valid.push({
                id: module.id,
                name: module.name,
                icon: String(module.icon || "application-x-executable"),
                description: String(module.description || ""),
                provider: provider,
                enabled: module.enabled === true,
                implemented: module.implemented === true,
                order: Number(module.order || (i + 1) * 10)
            })
        }
        root.modules = valid.length > 0 ? valid : root.builtinModules
    }

    function loadUserOverrides(raw) {
        var parsed = {}
        try {
            var value = JSON.parse(String(raw || ""))
            if (value && value.version === 1 && value.modules && typeof value.modules === "object" && !Array.isArray(value.modules)) parsed = value.modules
        } catch (error) {
            // A missing or malformed optional user file leaves safe defaults.
        }
        var valid = {}
        for (var key in parsed) {
            if (/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(key) && typeof parsed[key] === "boolean") valid[key] = parsed[key]
        }
        root.userOverrides = valid
    }

    function moduleFor(id) {
        for (var i = 0; i < root.modules.length; i++) {
            if (root.modules[i].id === id) return root.modules[i]
        }
        return null
    }

    function isEnabled(id) {
        var module = root.moduleFor(id)
        if (!module || module.implemented !== true) return false
        if (root.userOverrides[id] !== undefined) return root.userOverrides[id] === true
        return module.enabled === true
    }

    function providerFor(id) {
        var module = root.moduleFor(id)
        var provider = module && module.provider ? String(module.provider) : String(id || "")
        return root.supportedProviders.indexOf(provider) !== -1 ? provider : ""
    }

    function enabledModuleIds() {
        var ids = []
        for (var i = 0; i < root.modules.length; i++) {
            if (root.isEnabled(root.modules[i].id)) ids.push(root.modules[i].id)
        }
        ids.sort(function(left, right) {
            return Number(root.moduleFor(left).order) - Number(root.moduleFor(right).order)
        })
        return ids
    }

    function moduleRows() {
        var rows = []
        var ids = root.enabledModuleIds()
        for (var i = 0; i < ids.length; i++) {
            var module = root.moduleFor(ids[i])
            rows.push({
                id: "module:" + module.id,
                kind: "module",
                moduleId: module.id,
                provider: root.providerFor(module.id),
                label: module.name,
                subtitle: module.description,
                detail: "Open module",
                icon: module.icon,
                order: module.order,
                keywords: module.id
            })
        }
        return rows
    }

    function summaries() {
        var rows = []
        for (var i = 0; i < root.modules.length; i++) {
            var module = root.modules[i]
            rows.push({
                id: module.id,
                name: module.name,
                description: module.description,
                enabled: root.isEnabled(module.id),
                implemented: module.implemented === true
            })
        }
        return rows
    }

    function setModuleEnabled(id, enabled) {
        var module = root.moduleFor(id)
        if (!module || module.implemented !== true) {
            root.lastError = "Unknown or unavailable Command Center module: " + id
            return false
        }
        var previous = root.userOverrides
        var next = {}
        for (var key in previous) next[key] = previous[key]
        next[id] = enabled === true
        root.lastSaveOk = false
        root.userOverrides = next
        root.userFile.setText(JSON.stringify({ version: 1, modules: next }, null, 2) + "\n")
        if (!root.lastSaveOk) {
            root.userOverrides = previous
            root.lastError = "Could not persist Command Center module state."
            return false
        }
        root.lastError = ""
        return true
    }

    property FileView defaultFile: FileView {
        path: root.defaultModulesPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadDefaults(text())
        onFileChanged: reload()
        onLoadFailed: root.loadDefaults("")
    }

    property FileView userFile: FileView {
        path: root.userModulesPath
        watchChanges: true
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadUserOverrides(text())
        onFileChanged: reload()
        onLoadFailed: root.loadUserOverrides("")
        onSaved: root.lastSaveOk = true
        onSaveFailed: root.lastSaveOk = false
    }

    Component.onCompleted: {
        root.defaultFile.reload()
        root.userFile.reload()
    }
}
