import QtQuick

// T14 third-party bar-widget fixture. All injected objects are inspected by
// the parent test after BarWidgetSlot has loaded this item.
Item {
    property var shell: null
    property var pluginRegistry: null
    property var bar: null
    property var barWidgetRegistry: null
    property var appLibrary: null
    property var manifest: null
    property var shellConfig: null
    property var settings: ({})
    property string moduleName: ""
    implicitWidth: 1
    implicitHeight: 1
}
