import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// A bounded, explicit speed-test surface. Omarchy's worker/helper lifecycle
// is retained: download and upload run as separate phases and closing the
// surface terminates traffic instead of leaving it behind the UI.
Item {
    id: root

    property string aureliaPath: ""
    property var shell: null
    property var manifest: ({})
    property bool opened: false
    property string connectionName: ""
    property bool running: false
    property bool expectedStop: false
    property bool pendingRun: false
    property string phase: ""
    property string downloadMbps: ""
    property string uploadMbps: ""
    property string error: ""
    property string stderrText: ""

    readonly property string sourceBinRoot: decodeURIComponent(
        String(Qt.resolvedUrl("../../bin")).replace(/^file:\/\//, "")
    )
    readonly property string binRoot: aureliaPath !== "" ? aureliaPath + "/bin" : sourceBinRoot
    readonly property string speedBin: binRoot + "/aurelia-network-speedtest"
    readonly property string statusBin: binRoot + "/aurelia-network-status"
    readonly property real downloadValue: Number(downloadMbps) > 0 ? Number(downloadMbps) : 0
    readonly property real uploadValue: Number(uploadMbps) > 0 ? Number(uploadMbps) : 0

    function open(payloadJson) {
        var payload = {}
        try { payload = JSON.parse(payloadJson || "{}") || {} } catch (errorValue) {}
        connectionName = payload.connection !== undefined ? String(payload.connection) : ""
        if (connectionName === "") refreshConnectionName()
        opened = true
        runSpeedTest()
    }

    function close() {
        opened = false
        pendingRun = false
        phaseTimer.stop()
        phase = ""
        running = false
        if (speedProc.running) {
            expectedStop = true
            speedProc.running = false
        }
    }

    function dismiss() {
        if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "aurelia.speedtest")
        else close()
    }

    function refreshConnectionName() {
        statusProc.running = false
        statusProc.running = true
    }

    function updateLine(line) {
        if (!root.opened || root.expectedStop) return
        var value = Number(String(line || "").trim())
        if (!isFinite(value) || value < 0) return
        if (phase === "down") downloadMbps = String(value)
        else if (phase === "up") uploadMbps = String(value)
    }

    function runSpeedTest() {
        if (speedProc.running) {
            if (expectedStop) pendingRun = true
            return
        }
        error = ""
        downloadMbps = ""
        uploadMbps = ""
        running = true
        startPhase("down")
    }

    function startPhase(nextPhase) {
        expectedStop = false
        phase = nextPhase
        stderrText = ""
        speedProc.command = [speedBin, nextPhase]
        speedProc.running = true
        phaseTimer.restart()
    }

    function stopPhase() {
        phaseTimer.stop()
        if (speedProc.running) {
            expectedStop = true
            speedProc.running = false
        } else {
            finishPhase()
        }
    }

    function finishPhase() {
        if (phase === "down") {
            startPhase("up")
            return
        }
        phase = ""
        running = false
        expectedStop = false
    }

    Process {
        id: speedProc
        command: []
        stdout: SplitParser { onRead: function(line) { root.updateLine(line) } }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.stderrText = String(text || "").trim()
                if (root.error !== "" && root.stderrText !== "") root.error = root.stderrText
            }
        }
        onExited: function(exitCode) {
            phaseTimer.stop()
            if (root.expectedStop) {
                root.expectedStop = false
                if (root.pendingRun && root.opened) {
                    root.pendingRun = false
                    Qt.callLater(root.runSpeedTest)
                }
                return
            }
            if (exitCode !== 0) {
                root.error = root.stderrText || "Speed test failed"
                root.phase = ""
                root.running = false
                return
            }
            root.finishPhase()
        }
    }

    Timer {
        id: phaseTimer
        interval: 5000
        repeat: false
        onTriggered: root.stopPhase()
    }

    Process {
        id: statusProc
        command: [root.statusBin]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var fields = String(text || "").trim().split("\t")
                if (fields[0] === "wifi") root.connectionName = fields[1] || "Wi-Fi"
                else if (fields[0] === "ethernet") root.connectionName = "Ethernet"
            }
        }
    }

    PanelWindow {
        id: speedWindow
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: root.opened && speedWindow.screen !== null
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "aurelia-network-speedtest"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.78)
            MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
        }

        FocusScope {
            anchors.fill: parent
            focus: root.opened
            Keys.onEscapePressed: root.dismiss()

            Rectangle {
                width: 440
                height: 272
                anchors.centerIn: parent
                radius: Theme.radiusLg
                color: Theme.bgBase
                border.color: Theme.border
                border.width: Theme.borderWidthDefault

                MouseArea { anchors.fill: parent; onClicked: {} }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXl
                    spacing: Theme.spacingMd

                    Text {
                        Layout.fillWidth: true
                        text: root.connectionName !== "" ? root.connectionName : "Network speed test"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Theme.fontWeightBold
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Theme.spacingMd
                        Repeater {
                            model: [
                                { label: "DOWNLOAD", value: root.downloadValue, live: root.phase === "down" },
                                { label: "UPLOAD", value: root.uploadValue, live: root.phase === "up" }
                            ]
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.spacingXs
                                Text { Layout.fillWidth: true; text: modelData.label; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs; horizontalAlignment: Text.AlignHCenter }
                                Text { Layout.fillWidth: true; text: modelData.value.toFixed(1); color: modelData.live ? Theme.accent : Theme.text; font.family: Theme.fontFamily; font.pixelSize: 30; font.weight: Theme.fontWeightBold; horizontalAlignment: Text.AlignHCenter }
                                Text { Layout.fillWidth: true; text: "Mbps"; color: Theme.textSecondary; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs; horizontalAlignment: Text.AlignHCenter }
                                Rectangle { Layout.fillWidth: true; height: 6; radius: 3; color: Theme.surface; Rectangle { width: Math.min(1, modelData.value / 1000) * parent.width; height: parent.height; radius: 3; color: Theme.accent } }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.error !== "" ? root.error : (root.running ? (root.phase === "down" ? "Measuring download…" : "Measuring upload…") : "Complete")
                        color: root.error !== "" ? Theme.error : Theme.textSecondary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 96; height: 32; radius: Theme.radiusSm
                            color: Theme.surface; border.color: Theme.border
                            Text { anchors.centerIn: parent; text: "Again"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                            MouseArea { anchors.fill: parent; onClicked: root.runSpeedTest() }
                        }
                        Rectangle {
                            width: 96; height: 32; radius: Theme.radiusSm
                            color: Theme.accent
                            Text { anchors.centerIn: parent; text: "Close"; color: Theme.bgBase; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs }
                            MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
                        }
                    }
                }
            }
        }
    }
}
