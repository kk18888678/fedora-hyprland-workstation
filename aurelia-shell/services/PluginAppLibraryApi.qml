import QtQuick

// Read-only application catalogue for third-party menu surfaces. The host
// supplies detached row data and icon sources; launch/removal remain outside
// this capability until an explicit, owner-checked action API is required.
QtObject {
    id: api

    required property string ownerPluginId
    property var _rows: null
    property var _iconSource: null

    function appRows(query) {
        if (!api._rows) return []
        try {
            return JSON.parse(JSON.stringify(api._rows(String(query || ""))))
        } catch (e) {
            return []
        }
    }

    function iconSource(icon) {
        return api._iconSource ? String(api._iconSource(String(icon || "")) || "") : ""
    }
}
