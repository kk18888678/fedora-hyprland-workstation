import QtQuick

Item {
    function close() {
        throw new Error("intentional close callback failure")
    }
}
