import QtQuick

// Resident bar-control router. It validates active bar identity against the
// manifest registry and delegates actual state writes to ShellConfig's
// BarConfigOperations owner.
QtObject {
    id: root

    property var pluginRegistry: null

    function finish(error) {
        if (error) return String(error)
        if (!root.pluginRegistry) return "shell configuration is unavailable"
        root.pluginRegistry.lastError = ""
        root.pluginRegistry.registryRevision++
        root.pluginRegistry.pluginsChanged()
        return ""
    }

    function mutate(method, value) {
        var registry = root.pluginRegistry
        var config = registry ? registry.shellConfig : null
        var operations = config ? config.barOperations : null
        if (!operations || typeof operations[method] !== "function")
            return "shell configuration is unavailable"
        var error = value === undefined ? operations[method]() : operations[method](value)
        return root.finish(error)
    }

    function useBar(id) {
        var registry = root.pluginRegistry
        var pluginId = String(id || "")
        var manifest = registry ? registry.installedPlugins[pluginId] : null
        if (!manifest || !registry.hasKind(manifest, "bar")) return "unknown bar: " + pluginId
        if (!registry.isEnabled(pluginId)) return "bar is disabled: " + pluginId
        return root.mutate("useBar", pluginId)
    }

    function resetBar() { return root.mutate("resetBar") }
    function restoreBarDefaults() { return root.mutate("restoreBarDefaults") }
    function setBarPosition(position) { return root.mutate("setBarPosition", String(position || "")) }
    function setBarTransparent(value) { return root.mutate("setBarTransparent", String(value || "")) }
}
