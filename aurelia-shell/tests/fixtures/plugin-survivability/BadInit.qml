import QtQuick

Item {
    Component.onCompleted: {
        throw new Error("intentional initialization failure")
    }

    function aureliaInitialize() {
        throw new Error("intentional host initialization failure")
    }
}
