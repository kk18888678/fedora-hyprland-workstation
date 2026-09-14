import QtQuick

// Hyprland can leave a long-lived layer surface at its old global origin when
// a monitor is moved. Keep the remap guard on the mapped panel so the resident
// bar host and its configuration remain alive while only the affected surface
// is briefly unmapped and remapped.
Item {
    id: root

    required property var window
    readonly property var screen: root.window ? root.window.screen : null
    property bool remapping: false

    visible: false

    Timer {
        id: settleTimer
        interval: 200
        repeat: false
        onTriggered: root.remapping = true
    }

    Timer {
        interval: 50
        repeat: false
        running: root.remapping
        onTriggered: root.remapping = false
    }

    Connections {
        target: root.screen

        function onXChanged() { settleTimer.restart() }
        function onYChanged() { settleTimer.restart() }
    }
}
