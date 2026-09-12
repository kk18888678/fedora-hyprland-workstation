import QtQuick

Item {
    function ipcAction(argument) {
        throw new Error("intentional IPC callback failure")
    }
}
