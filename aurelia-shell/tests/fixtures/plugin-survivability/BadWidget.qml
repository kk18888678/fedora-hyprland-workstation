import QtQuick

Item {
    function open(payloadJson) {
        throw new Error("intentional bar widget callback failure")
    }
}
