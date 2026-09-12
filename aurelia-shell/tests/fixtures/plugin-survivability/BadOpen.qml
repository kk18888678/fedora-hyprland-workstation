import QtQuick

Item {
    function open(payloadJson) {
        throw new Error("intentional open callback failure")
    }
}
