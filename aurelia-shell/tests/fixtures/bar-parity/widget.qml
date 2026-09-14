import QtQuick

// Minimal first-party widget used only by the T54 orientation fixture.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: ""
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barWidgetRegistry: null

    implicitWidth: 120
    implicitHeight: 32

    Rectangle {
        anchors.fill: parent
        color: "#101010"
    }
}
