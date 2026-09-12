import QtQuick
import Quickshell
import Quickshell.Io

// Manifest-backed menu data and its bounded provider/action contract. Menu
// data can select an approved Aurelia action, but cannot provide an executable
// shell string or an arbitrary provider name.
QtObject {
    id: root

    property var shell: null
    property var pluginRegistry: null
    property var pluginHost: null
    property string aureliaPath: ""
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHomeOverride: Quickshell.env("XDG_CONFIG_HOME") || ""
    readonly property string configHome: configHomeOverride.charAt(0) === "/"
        ? configHomeOverride : (home + "/.config")
    readonly property string shippedMenuPath: pathFromUrl(Qt.resolvedUrl("menu.json"))
    readonly property string userMenuPath: configHome + "/aurelia/menu.json"
    readonly property var allowedActions: ["open-command-center", "reload-plugins", "toggle-bar"]
    readonly property var allowedProviders: ["plugins"]
    readonly property var allowedWhen: ["always", "bar-visible", "plugins-present"]
    readonly property var allowedChecked: ["bar-visible", "bar-hidden"]
    property var shippedItems: []
    property var userItems: []
    property var items: []
    property var rows: []
    property string lastError: ""

    signal menuChanged()

    function pathFromUrl(value) {
        var text = String(value || "")
        return text.indexOf("file://") === 0 ? decodeURIComponent(text.substring(7)) : text
    }

    function cloneJson(value) {
        try {
            return JSON.parse(JSON.stringify(value))
        } catch (error) {
            return null
        }
    }

    function validateItem(value) {
        if (!value || typeof value !== "object" || Array.isArray(value)) return null
        var allowed = ["id", "label", "icon", "description", "action", "provider", "when", "checked", "order"]
        var keys = Object.keys(value)
        for (var i = 0; i < keys.length; i++) if (allowed.indexOf(keys[i]) === -1) return null
        if (typeof value.id !== "string" || !/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(value.id) || value.id.indexOf("..") !== -1)
            return null
        if (typeof value.label !== "string" || value.label.trim() === "" || value.label.length > 256) return null
        if (value.icon !== undefined && (typeof value.icon !== "string" || value.icon.length > 128)) return null
        if (value.description !== undefined && (typeof value.description !== "string" || value.description.length > 512)) return null
        var action = value.action === undefined ? "" : String(value.action)
        var provider = value.provider === undefined ? "" : String(value.provider)
        if (!action && !provider) return null
        if (action && root.allowedActions.indexOf(action) === -1) return null
        if (provider && root.allowedProviders.indexOf(provider) === -1) return null
        if (value.when !== undefined && root.allowedWhen.indexOf(String(value.when)) === -1) return null
        if (value.checked !== undefined && root.allowedChecked.indexOf(String(value.checked)) === -1) return null
        if (value.order !== undefined && (typeof value.order !== "number" || !isFinite(value.order) || value.order < 0 || value.order > 100000)) return null
        return {
            id: value.id,
            label: value.label,
            icon: String(value.icon || "system-run"),
            description: String(value.description || ""),
            action: action,
            provider: provider,
            when: String(value.when || "always"),
            checked: String(value.checked || ""),
            order: Number(value.order || 0)
        }
    }

    function parseItems(raw, sourceName) {
        var parsed
        try {
            parsed = JSON.parse(String(raw || ""))
        } catch (error) {
            if (sourceName === "shipped") root.lastError = "Shipped Aurelia menu data is invalid."
            return []
        }
        var values = Array.isArray(parsed) ? parsed : (parsed && parsed.version === 1 ? parsed.items : null)
        if (!Array.isArray(values)) {
            if (sourceName === "shipped") root.lastError = "Aurelia menu data has an unsupported shape."
            return []
        }
        var result = []
        for (var i = 0; i < values.length && i < 256; i++) {
            var item = root.validateItem(values[i])
            if (item) result.push(item)
        }
        return result
    }

    function loadShipped(raw) {
        root.shippedItems = root.parseItems(raw, "shipped")
        root.rebuild()
    }

    function loadUser(raw) {
        root.userItems = root.parseItems(raw, "user")
        root.rebuild()
    }

    function rebuild() {
        var merged = {}
        for (var i = 0; i < root.shippedItems.length; i++) merged[root.shippedItems[i].id] = root.shippedItems[i]
        for (var j = 0; j < root.userItems.length; j++) merged[root.userItems[j].id] = root.userItems[j]
        var ids = Object.keys(merged)
        ids.sort(function(left, right) {
            var order = Number(merged[left].order) - Number(merged[right].order)
            return order !== 0 ? order : left.localeCompare(right)
        })
        var next = []
        for (var k = 0; k < ids.length; k++) next.push(merged[ids[k]])
        root.items = next
        root.rebuildRows()
        root.menuChanged()
    }

    function pluginCatalog() {
        try {
            if (root.pluginHost && typeof root.pluginHost.catalog === "function") {
                var hostCatalog = root.pluginHost.catalog()
                return hostCatalog && Array.isArray(hostCatalog.plugins) ? hostCatalog.plugins : []
            }
            if (root.pluginRegistry && typeof root.pluginRegistry.pluginCatalog === "function") {
                var registryCatalog = root.pluginRegistry.pluginCatalog()
                return registryCatalog && Array.isArray(registryCatalog.plugins) ? registryCatalog.plugins : []
            }
        } catch (error) {
            root.lastError = "Plugin menu provider failed safely."
        }
        return []
    }

    function isBarVisible() {
        try {
            var bar = root.pluginHost && typeof root.pluginHost.activeBar === "function"
                ? root.pluginHost.activeBar() : null
            return !!(bar && bar.barHidden !== true)
        } catch (error) {
            return false
        }
    }

    function visible(item) {
        if (item.when === "always") return true
        if (item.when === "bar-visible") return root.isBarVisible()
        if (item.when === "plugins-present") return root.pluginCatalog().length > 0
        return false
    }

    function checkedFor(item) {
        if (item.checked === "bar-visible") return root.isBarVisible()
        if (item.checked === "bar-hidden") return !root.isBarVisible()
        return false
    }

    function menuRow(item, label, subtitle, detail, suffix) {
        return {
            id: "menu:" + item.id + (suffix ? ":" + suffix : ""),
            kind: suffix ? "menu-provider" : "menu-item",
            menuId: item.id,
            menuAction: item.action || "open-command-center",
            pluginId: suffix || "",
            label: label,
            subtitle: subtitle,
            detail: detail,
            icon: item.icon,
            checked: suffix ? false : root.checkedFor(item),
            order: Number(item.order || 0) + (suffix ? 1 : 0),
            keywords: [item.id, label, subtitle, detail, suffix || ""].join(" ")
        }
    }

    function rebuildRows() {
        var next = []
        for (var i = 0; i < root.items.length; i++) {
            var item = root.items[i]
            if (!root.visible(item)) continue
            if (item.provider === "plugins") {
                var plugins = root.pluginCatalog()
                for (var pluginIndex = 0; pluginIndex < plugins.length; pluginIndex++) {
                    var plugin = plugins[pluginIndex]
                    if (!plugin || typeof plugin.id !== "string") continue
                    var state = plugin.enabled === true ? "Enabled" : "Disabled"
                    var source = String(plugin.source || (plugin.firstParty ? "first-party" : "user"))
                    next.push(root.menuRow(item, String(plugin.name || plugin.id), state + " · " + source,
                        String(plugin.id) + " · " + String(plugin.kind || "plugin"), String(plugin.id)))
                }
            } else {
                next.push(root.menuRow(item, item.label, item.description, "", ""))
            }
        }
        next.sort(function(left, right) {
            var order = Number(left.order) - Number(right.order)
            return order !== 0 ? order : String(left.label).localeCompare(String(right.label))
        })
        root.rows = next
    }

    function open(payloadJson) {
        root.lastError = ""
        root.rebuildRows()
    }

    function activate(row) {
        if (!row || root.allowedActions.indexOf(String(row.menuAction || "")) === -1) {
            root.lastError = "Menu action is not approved."
            return false
        }
        if (!root.shell) {
            root.lastError = "Aurelia Shell API is unavailable."
            return false
        }
        var action = String(row.menuAction)
        var result = "not-loaded"
        try {
            if (action === "open-command-center" && typeof root.shell.summon === "function")
                result = root.shell.summon("aurelia.launcher", "{}")
            else if (action === "reload-plugins" && typeof root.shell.rescanPlugins === "function")
                result = root.shell.rescanPlugins()
            else if (action === "toggle-bar" && typeof root.shell.toggle === "function")
                result = root.shell.toggle("aurelia.bar", "{}")
        } catch (error) {
            root.lastError = "Aurelia menu action failed safely."
            return false
        }
        if (action === "toggle-bar") return result === "ok" || result === "closed"
        return result === "ok" || result === "pending"
    }

    property FileView shippedFile: FileView {
        path: root.shippedMenuPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadShipped(text())
        onFileChanged: root.loadShipped(text())
        onLoadFailed: root.loadShipped("")
    }

    property FileView userFile: FileView {
        path: root.userMenuPath
        watchChanges: true
        blockLoading: true
        blockWrites: true
        printErrors: false
        onLoaded: root.loadUser(text())
        onFileChanged: root.loadUser(text())
        onLoadFailed: root.loadUser("")
    }

    property Connections registryConnection: Connections {
        target: root.pluginRegistry
        function onPluginsChanged() { root.rebuildRows() }
    }

    Component.onCompleted: {
        root.shippedFile.reload()
        root.userFile.reload()
        root.rebuild()
    }
}
