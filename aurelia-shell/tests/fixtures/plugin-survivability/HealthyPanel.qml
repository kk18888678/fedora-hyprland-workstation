import QtQuick

Item {
    implicitWidth: 12
    implicitHeight: 12
    visible: false

    function health(argument) {
        return argument === "{}" ? "healthy" : "healthy-unexpected-argument"
    }

    function open(payloadJson) {
        visible = true
    }

    function close() {
        visible = false
    }

    function isVisible() {
        return visible
    }
}
