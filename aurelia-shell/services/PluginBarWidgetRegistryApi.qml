import QtQuick

// Detached bar-widget catalogue snapshot for third-party consumers. Mutating
// this object's local widgets property cannot change the host registry.
QtObject {
    id: api

    property var widgets: ({})
    property int revision: 0

    function cloneJson(value) {
        try {
            return JSON.parse(JSON.stringify(value))
        } catch (e) {
            return null
        }
    }

    function metadataFor(id) {
        var entry = api.widgets[String(id || "")]
        return entry ? api.cloneJson(entry.metadata || {}) : null
    }

    function availableIds() {
        var ids = Object.keys(api.widgets || {})
        ids.sort()
        return ids
    }

    function has(id) {
        return api.widgets[String(id || "")] !== undefined
    }

    function snapshotFor(id) {
        var entry = api.widgets[String(id || "")]
        return entry ? api.cloneJson(entry) : null
    }
}
