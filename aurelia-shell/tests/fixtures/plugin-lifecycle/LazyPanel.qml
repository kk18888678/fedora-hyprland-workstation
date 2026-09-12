import QtQuick

Item {
    property bool opened: false

    function open(payloadJson) {
        opened = true
        return "lazy-open"
    }

    function close() {
        opened = false
        return "lazy-close"
    }

    function isVisible() {
        return opened
    }
}
