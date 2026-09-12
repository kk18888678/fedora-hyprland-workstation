import QtQuick

// Lifecycle/settings facade scoped to one plugin identity. Every callback is
// closed over that identity by PluginHost; caller-supplied foreign IDs fail.
// This is a supported API boundary, not a same-process QML sandbox.
QtObject {
    id: api

    required property string pluginId
    property string compatibilityId: ""
    property var bar: null
    property var appLibrary: null
    property var barConfig: ({})
    property var settings: ({})

    property var _serviceLookup: null
    property var _summon: null
    property var _hide: null
    property var _toggle: null
    property var _isOpen: null
    property var _settingsFor: null
    property var _updateSettings: null
    property var _resetSettings: null

    function owns(id) {
        var requested = String(id || "")
        return requested === api.pluginId || (api.compatibilityId !== "" && requested === api.compatibilityId)
    }

    function serviceFor(id) {
        return api.owns(id) && api._serviceLookup ? api._serviceLookup() : null
    }

    function summon(id, payloadJson) {
        return api.owns(id) && api._summon ? api._summon(String(payloadJson || "{}")) : false
    }

    function hide(id) {
        return api.owns(id) && api._hide ? api._hide() : false
    }

    function toggle(id, payloadJson) {
        return api.owns(id) && api._toggle ? api._toggle(String(payloadJson || "{}")) : false
    }

    function isPluginOpen(id) {
        return api.owns(id) && api._isOpen ? api._isOpen() : false
    }

    function settingsFor(id, selector) {
        return api.owns(id) && api._settingsFor ? api._settingsFor(selector || ({})) : ({})
    }

    function updateEntryInline(id, settings, selector) {
        return api.owns(id) && api._updateSettings
            ? api._updateSettings(settings, selector || ({})) : false
    }

    function resetEntryInline(id, selector) {
        return api.owns(id) && api._resetSettings
            ? api._resetSettings(selector || ({})) : false
    }
}
