import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "Model.js" as Model

// Centered Wi-Fi share surface adapted from Omarchy's QR panel. The QR
// generator emits a metadata line followed by a validated square matrix; the
// password is fetched only after the user explicitly asks to reveal it.
Item {
    id: root

    property string aureliaPath: ""
    property var shell: null
    property var manifest: ({})
    property bool opened: false
    property string iface: ""
    property string ssid: ""
    property bool secured: false
    property var qrRows: []
    property int qrSize: 0
    property string error: ""
    property bool loading: false
    property bool expectedStop: false
    property bool pendingShow: false
    property string pendingIface: ""
    property string password: ""
    property bool passwordVisible: false
    property string passwordError: ""
    property bool passwordExpectedStop: false

    readonly property string sourceBinRoot: decodeURIComponent(
        String(Qt.resolvedUrl("../../bin")).replace(/^file:\/\//, "")
    )
    readonly property string binRoot: aureliaPath !== "" ? aureliaPath + "/bin" : sourceBinRoot
    readonly property string qrBin: binRoot + "/aurelia-network-qr"
    readonly property string passwordBin: binRoot + "/aurelia-network-password"
    readonly property bool showingQr: qrSize > 0 && !loading && error === ""

    function validInterface(value) { return /^[A-Za-z0-9_.-]{1,32}$/.test(String(value || "")) }

    function open(payloadJson) {
        var payload = {}
        try { payload = JSON.parse(payloadJson || "{}") || {} } catch (errorValue) {}
        var requestedIface = validInterface(payload.iface) ? String(payload.iface) : ""
        ssid = payload.ssid !== undefined ? String(payload.ssid) : ""
        generate(requestedIface)
        opened = true
        Qt.callLater(function() { if (opened) keyCatcher.forceActiveFocus() })
    }

    function close() {
        opened = false
        pendingShow = false
        pendingIface = ""
        if (qrProc.running) {
            expectedStop = true
            qrProc.running = false
        }
        if (passwordProc.running) {
            passwordExpectedStop = true
            passwordProc.running = false
        }
        qrSize = 0
        qrRows = []
        error = ""
        loading = false
        iface = ""
        ssid = ""
        secured = false
        password = ""
        passwordVisible = false
        passwordError = ""
    }

    function dismiss() {
        if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "aurelia.wifiqr")
        else close()
    }

    function generate(requestedIface) {
        if (qrProc.running) {
            pendingShow = true
            pendingIface = requestedIface
            if (!expectedStop) {
                expectedStop = true
                qrProc.running = false
            }
            return
        }
        qrSize = 0
        qrRows = []
        error = ""
        loading = true
        expectedStop = false
        iface = ""
        secured = false
        password = ""
        passwordVisible = false
        passwordError = ""
        passwordExpectedStop = false
        if (passwordProc.running) {
            passwordExpectedStop = true
            passwordProc.running = false
        }
        qrProc.command = requestedIface
            ? ["/usr/bin/timeout", "--kill-after=1s", "10s", qrBin, "--meta", requestedIface]
            : ["/usr/bin/timeout", "--kill-after=1s", "10s", qrBin, "--meta"]
        qrProc.running = true
    }

    function updateQr(raw) {
        var parsed = Model.parseQrOutput(raw)
        qrRows = parsed.matrix.rows
        qrSize = parsed.matrix.size
        if (parsed.meta.ssid !== "") ssid = parsed.meta.ssid
        if (parsed.meta.iface !== "" && validInterface(parsed.meta.iface)) iface = parsed.meta.iface
        secured = parsed.meta.security !== "" && parsed.meta.security !== "nopass"
        if (qrSize > 0) error = ""
    }

    function togglePassword() {
        if (passwordVisible) { passwordVisible = false; return }
        if (password !== "") { passwordVisible = true; return }
        if (passwordProc.running || !validInterface(iface)) return
        passwordError = ""
        passwordExpectedStop = false
        passwordProc.command = ["/usr/bin/timeout", "--kill-after=1s", "5s", passwordBin, iface]
        passwordProc.running = true
    }

    Process {
        id: qrProc
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (!root.expectedStop) root.updateQr(text)
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (!root.expectedStop) root.error = String(text || "").trim()
        }
        onExited: function(exitCode) {
            root.loading = false
            if (root.pendingShow) {
                root.pendingShow = false
                Qt.callLater(function() { root.generate(root.pendingIface) })
                return
            }
            if (root.expectedStop) return
            if (exitCode !== 0 || root.qrSize === 0) {
                root.qrSize = 0
                root.qrRows = []
                if (root.error === "") root.error = "Could not generate the Wi-Fi QR code"
            }
        }
    }

    Process {
        id: passwordProc
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (root.opened && !root.passwordExpectedStop)
                root.password = String(text || "").trim()
        }
        onExited: function(exitCode) {
            if (root.passwordExpectedStop || !root.opened) return
            if (exitCode === 0 && root.password !== "") root.passwordVisible = true
            else root.passwordError = "Could not read the Wi-Fi password"
        }
    }

    PanelWindow {
        id: qrWindow
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: root.opened && qrWindow.screen !== null
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "aurelia-network-qr"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.78)
            MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
        }

        Item {
            id: keyCatcher
            anchors.fill: parent
            focus: root.opened
            Keys.onEscapePressed: root.dismiss()

            Item {
                id: contentFrame
                anchors.centerIn: parent
                width: qrContent.implicitWidth
                height: qrContent.implicitHeight
                scale: Math.min(1,
                    (parent.width - Theme.spacingXxl * 2) / Math.max(1, width),
                    (parent.height - Theme.spacingXxl * 2) / Math.max(1, height))

                MouseArea { anchors.fill: parent; onClicked: {} }

                Column {
                    id: qrContent
                    spacing: Theme.spacingLg

                    Text {
                        width: Math.min(320, Math.max(120, parent.width))
                        text: (root.ssid || "Wi-Fi").toUpperCase()
                        color: Qt.rgba(1, 1, 1, 0.65)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                        font.letterSpacing: 2
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: qrCanvas
                        visible: root.showingQr
                        property int moduleSize: root.qrSize > 0
                            ? Math.max(4, Math.floor(240 / root.qrSize)) : 0
                        width: root.qrSize * moduleSize
                        height: width
                        color: "white"
                        radius: Theme.radiusSm
                        anchors.horizontalCenter: parent.horizontalCenter

                        Grid {
                            anchors.fill: parent
                            columns: root.qrSize
                            Repeater {
                                model: root.qrSize * root.qrSize
                                delegate: Rectangle {
                                    required property int index
                                    property int matrixRow: Math.floor(index / root.qrSize)
                                    property int matrixColumn: index % root.qrSize
                                    width: qrCanvas.moduleSize
                                    height: qrCanvas.moduleSize
                                    color: root.qrRows[matrixRow].charAt(matrixColumn) === "1"
                                        ? "#111111" : "transparent"
                                }
                            }
                        }
                    }

                    Text {
                        visible: root.loading
                        text: "Generating QR code…"
                        color: Qt.rgba(1, 1, 1, 0.65)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }
                    Text {
                        visible: root.error !== ""
                        text: root.error
                        color: "#ff6b6b"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        wrapMode: Text.Wrap
                        width: 320
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        visible: root.showingQr
                        text: "Scan to join this network"
                        color: Qt.rgba(1, 1, 1, 0.65)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }
                    Text {
                        visible: root.showingQr && root.secured
                        text: root.passwordError !== "" ? root.passwordError
                            : (root.passwordVisible ? root.password : "Show password")
                        color: root.passwordError !== "" ? "#ff6b6b" : "white"
                        opacity: root.passwordVisible || root.passwordError !== "" ? 1 : 0.6
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        wrapMode: Text.WrapAnywhere
                        width: 320
                        horizontalAlignment: Text.AlignHCenter
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.togglePassword() }
                    }
                }
            }
        }
    }
}
