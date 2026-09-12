import QtQuick

Item {
    function open(payloadJson) {
        throw new Error("intentional callback failure")
    }
}
