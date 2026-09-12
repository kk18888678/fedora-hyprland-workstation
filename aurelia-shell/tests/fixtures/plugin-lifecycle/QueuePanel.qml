import QtQuick

Item {
    property var received: []
    property bool opened: false

    function open(payloadJson) {
        var next = received.slice()
        next.push(payloadJson)
        received = next
        opened = true
        return "queue-open"
    }

    function close() {
        opened = false
        return "queue-close"
    }

    function isVisible() {
        return opened
    }
}
