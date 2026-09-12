import QtQuick
import Quickshell
import Quickshell.Io

// T29 warning-stream fixture. It loads the real affected components in a
// disposable shell and deliberately creates two widget instances so IPC
// ownership and stale delayed callbacks are exercised.
ShellRoot {
    id: root

    readonly property string launcherSource: Quickshell.env("AURELIA_WARNING_LAUNCHER_SOURCE") || ""
    readonly property string displaySource: Quickshell.env("AURELIA_WARNING_DISPLAY_SOURCE") || ""
    readonly property string networkSource: Quickshell.env("AURELIA_WARNING_NETWORK_SOURCE") || ""
    readonly property string bluetoothSource: Quickshell.env("AURELIA_WARNING_BLUETOOTH_SOURCE") || ""
    readonly property string displayBackendRoot: Quickshell.env("AURELIA_WARNING_DISPLAY_BACKEND") || "/tmp"
    readonly property string resultPath: Quickshell.env("AURELIA_WARNING_RESULT") || ""

    property var launcher: null
    property var networkA: null
    property var networkB: null
    property var bluetoothA: null
    property var bluetoothB: null
    property bool launcherLoaded: false
    property bool displayLoaded: false
    property bool initialCaptured: false
    property bool switched: false
    property bool finished: false
    property bool initialNetworkAOwner: false
    property bool initialNetworkBOwner: false
    property bool initialBluetoothAOwner: false
    property bool initialBluetoothBOwner: false

    Item { id: ownerA; width: 1; height: 1 }
    Item { id: ownerB; width: 1; height: 1 }

    QtObject {
        id: fakeBar

        property int barSize: 26
        property int widgetRevision: 1
        property var owner: ownerA

        function anchorItemFor(widgetId) {
            var revision = widgetRevision
            return owner
        }

        function barAnchorItem() {
            return owner
        }

        function requestPopout(ownerObject, ownerId) {}
        function releasePopout(ownerObject) {}
    }

    function configureWidget(target, ownerObject) {
        if (!target) return
        target.bar = fakeBar
        target.barAnchorItem = ownerObject
    }

    Loader {
        id: launcherLoader
        source: root.launcherSource
        onLoaded: {
            root.launcher = item
            root.launcherLoaded = true
        }
    }

    Loader {
        id: displayLoader
        source: root.displaySource
        onLoaded: {
            root.displayLoaded = true
            item.backendRoot = root.displayBackendRoot
            displayLoader.active = false
        }
    }

    Loader {
        id: networkALoader
        source: root.networkSource
        onLoaded: {
            root.networkA = item
            root.configureWidget(item, ownerA)
        }
    }

    Loader {
        id: networkBLoader
        source: root.networkSource
        onLoaded: {
            root.networkB = item
            root.configureWidget(item, ownerB)
        }
    }

    Loader {
        id: bluetoothALoader
        source: root.bluetoothSource
        onLoaded: {
            root.bluetoothA = item
            root.configureWidget(item, ownerA)
        }
    }

    Loader {
        id: bluetoothBLoader
        source: root.bluetoothSource
        onLoaded: {
            root.bluetoothB = item
            root.configureWidget(item, ownerB)
        }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function captureInitial() {
        if (root.initialCaptured || !root.networkA || !root.networkB ||
            !root.bluetoothA || !root.bluetoothB) return
        root.initialCaptured = true
        root.initialNetworkAOwner = root.networkA.ipcOwner === true
        root.initialNetworkBOwner = root.networkB.ipcOwner === true
        root.initialBluetoothAOwner = root.bluetoothA.ipcOwner === true
        root.initialBluetoothBOwner = root.bluetoothB.ipcOwner === true
    }

    function switchOwner() {
        if (!root.initialCaptured || root.switched) return
        root.switched = true
        fakeBar.owner = ownerB
        fakeBar.widgetRevision++
    }

    function finish() {
        if (root.finished) return
        root.captureInitial()
        if (!root.initialCaptured || !root.switched || !root.networkA || !root.networkB ||
            !root.bluetoothA || !root.bluetoothB) {
            finishTimer.restart()
            return
        }
        root.finished = true
        resultFile.setText(JSON.stringify({
            launcherLoaded: root.launcherLoaded,
            displayLoaded: root.displayLoaded,
            initialNetworkAOwner: root.initialNetworkAOwner,
            initialNetworkBOwner: root.initialNetworkBOwner,
            initialBluetoothAOwner: root.initialBluetoothAOwner,
            initialBluetoothBOwner: root.initialBluetoothBOwner,
            finalNetworkAOwner: root.networkA.ipcOwner === true,
            finalNetworkBOwner: root.networkB.ipcOwner === true,
            finalBluetoothAOwner: root.bluetoothA.ipcOwner === true,
            finalBluetoothBOwner: root.bluetoothB.ipcOwner === true,
            bluezObjectManagerProbe: root.bluetoothA.hasBluezService(
                "org.freedesktop.DBus.ObjectManager method GetManagedObjects"
            ) === true,
            bluezInvalidProbe: root.bluetoothA.hasBluezService("org.bluez service only") === false
        }) + "\n")
    }

    Timer {
        id: captureTimer
        interval: 850
        repeat: false
        running: true
        onTriggered: root.captureInitial()
    }

    Timer {
        id: switchTimer
        interval: 1100
        repeat: false
        running: true
        onTriggered: root.switchOwner()
    }

    Timer {
        id: finishTimer
        interval: 1500
        repeat: false
        running: true
        onTriggered: root.finish()
    }

    Timer {
        interval: 9000
        repeat: false
        running: true
        onTriggered: Qt.quit()
    }
}
