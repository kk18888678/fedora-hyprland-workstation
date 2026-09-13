import QtQuick

// Bar-specific state transitions owned by ShellConfig. This component keeps
// bar policy out of the shared shell-state service while every write still
// goes through the owner's atomic persistence boundary.
QtObject {
    id: root

    property var owner: null

    function useBar(id) {
        var requested = String(id || "")
        if (!root.owner || !root.owner.isValidPluginId(requested))
            return "Invalid bar id: " + requested
        var next = root.owner.prepareMutationConfig()
        next.bar.id = requested
        if (!root.owner.persistConfig(next))
            return root.owner.lastError || "Could not persist active bar."
        return ""
    }

    function resetBar() {
        if (!root.owner) return "shell configuration is unavailable"
        var next = root.owner.prepareMutationConfig()
        next.disabledPlugins = root.owner.removeDisabledId(next.disabledPlugins, "aurelia.bar")
        next.bar.id = "aurelia.bar"
        if (!root.owner.persistConfig(next))
            return root.owner.lastError || "Could not reset active bar."
        return ""
    }

    function restoreBarDefaults() {
        if (!root.owner) return "shell configuration is unavailable"
        var next = root.owner.prepareMutationConfig()
        next.bar = root.owner.defaultBarConfig()
        next.disabledPlugins = root.owner.removeDisabledId(next.disabledPlugins, "aurelia.bar")
        if (!root.owner.persistConfig(next))
            return root.owner.lastError || "Could not restore bar defaults."
        return ""
    }

    function setBarPosition(position) {
        var requested = String(position || "")
        if (["top", "bottom", "left", "right"].indexOf(requested) === -1)
            return "position must be top, bottom, left, or right"
        if (!root.owner) return "shell configuration is unavailable"
        var next = root.owner.prepareMutationConfig()
        next.bar.position = requested
        if (!root.owner.persistConfig(next))
            return root.owner.lastError || "Could not persist bar position."
        return ""
    }

    function setBarTransparent(value) {
        var requested = String(value || "")
        if (["true", "false", "toggle"].indexOf(requested) === -1)
            return "transparent must be true, false, or toggle"
        if (!root.owner) return "shell configuration is unavailable"
        var next = root.owner.prepareMutationConfig()
        next.bar.transparent = requested === "toggle"
            ? next.bar.transparent !== true : requested === "true"
        if (!root.owner.persistConfig(next))
            return root.owner.lastError || "Could not persist bar transparency."
        return ""
    }
}
