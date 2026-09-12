import QtQuick

// Read-only, self-scoped registry view for a third-party plugin. The manifest
// is detached before it is exposed; this object never retains PluginRegistry.
QtObject {
    id: api

    required property string pluginId
    property var manifest: null
    property bool enabled: false
    property int registryRevision: 0
    property var _entryPointUrl: null
    property var _hasActiveFailure: null

    function cloneJson(value) {
        try {
            return JSON.parse(JSON.stringify(value))
        } catch (e) {
            return null
        }
    }

    readonly property var installedPlugins: {
        var snapshot = ({})
        var copy = api.cloneJson(api.manifest)
        if (copy) {
            var keys = Object.keys(copy)
            for (var i = 0; i < keys.length; i++)
                if (keys[i].indexOf("__") === 0) delete copy[keys[i]]
            snapshot[api.pluginId] = copy
        }
        return snapshot
    }

    function isEnabled(id) {
        return String(id || "") === api.pluginId && api.enabled === true
    }

    function isKnown(id) {
        return String(id || "") === api.pluginId && api.manifest !== null
    }

    function hasActiveRuntimeFailure(id, kind) {
        return String(id || "") === api.pluginId && api._hasActiveFailure
            ? api._hasActiveFailure(String(kind || "")) : false
    }

    function resolveEnabledId(id) {
        return String(id || "") === api.pluginId && api.enabled === true ? api.pluginId : ""
    }

    function entryPointUrl(candidate, kind) {
        var candidateId = typeof candidate === "string" ? candidate : (candidate ? candidate.id : "")
        if (String(candidateId || "") !== api.pluginId || !api.enabled) return ""
        return api._entryPointUrl ? api._entryPointUrl(String(kind || "")) : ""
    }
}
