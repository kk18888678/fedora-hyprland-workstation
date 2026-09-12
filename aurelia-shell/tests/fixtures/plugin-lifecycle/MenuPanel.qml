import QtQuick

Item {
    property bool opened: false

    function open(payloadJson) {
        opened = true
        return "menu-open"
    }

    function close() {
        opened = false
        return "menu-close"
    }

    function isVisible() {
        return opened
    }
}
