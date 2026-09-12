import QtQuick

Item {
    property bool opened: false

    function open(payloadJson) {
        opened = true
        return "kept-open"
    }

    function close() {
        opened = false
        return "kept-close"
    }

    function toggle(payloadJson) {
        opened = !opened
        return opened ? "kept-open" : "kept-close"
    }

    function isVisible() {
        return opened
    }
}
