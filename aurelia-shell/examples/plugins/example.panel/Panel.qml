import QtQuick

// Minimal authoring example. The host injects optional properties after the
// Loader has constructed this Item, so every optional property has a safe
// default and no host object is required during construction.
Item {
    id: root

    property string aureliaPath: ""
    property var shell: null
    property var appLibrary: null
    property var manifest: null
    property var pluginRegistry: null
    property var settings: ({})
    property bool openState: false

    implicitWidth: 360
    implicitHeight: 180
    visible: root.openState

    function open(payloadJson) {
        root.openState = true
        return "ok"
    }

    function close() {
        root.openState = false
        return "ok"
    }
}
