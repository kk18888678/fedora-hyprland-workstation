import QtQuick

// Narrow bar facade. Scalar state is detached; callbacks are owner-bound by
// PluginHost and never expose the active Bar object or arbitrary widget IDs.
QtObject {
    id: api

    required property string ownerPluginId
    property string instanceId: ownerPluginId
    property bool barHidden: false
    property int barSize: 0
    property string position: "top"
    property bool vertical: false
    property string activePopoutId: ""

    property var _requestPopout: null
    property var _releasePopout: null
    property var _invoke: null
    property var _registerClickTarget: null
    property var _unregisterClickTarget: null

    function requestPopout(requestedId) {
        var requested = String(requestedId || "")
        if (requested !== "" && requested !== api.instanceId && requested !== api.ownerPluginId) return false
        return api._requestPopout ? api._requestPopout() : false
    }

    function releasePopout(requestedId) {
        var requested = String(requestedId || "")
        if (requested !== "" && requested !== api.instanceId && requested !== api.ownerPluginId) return false
        return api._releasePopout ? api._releasePopout() : false
    }

    function invoke(method, argument) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(String(method || ""))) return "invalid-method"
        return api._invoke ? api._invoke(String(method), argument) : "not-loaded"
    }

    function registerClickTarget(requestedId) {
        var requested = String(requestedId || "")
        if (requested !== "" && requested !== api.instanceId && requested !== api.ownerPluginId) return false
        return api._registerClickTarget ? api._registerClickTarget() : false
    }

    function unregisterClickTarget(requestedId) {
        var requested = String(requestedId || "")
        if (requested !== "" && requested !== api.instanceId && requested !== api.ownerPluginId) return false
        return api._unregisterClickTarget ? api._unregisterClickTarget() : false
    }

    function isPopoutActive() {
        return api.activePopoutId === api.instanceId || api.activePopoutId === api.ownerPluginId
    }
}
