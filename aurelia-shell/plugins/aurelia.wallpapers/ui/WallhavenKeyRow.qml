import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../../theme"
import "../../../ui"

// Wallhaven API-key management row. The key is written through the
// `aurelia-wallpaper wallhaven key --set` stdin contract, never through argv,
// and the stored status is re-read after every mutation. This component owns
// no other state and never performs a search itself.
Item {
    id: keyRow

    property string wallpaperBin: ""
    property string status: "unknown"
    property string pendingKey: ""

    signal changed()

    implicitHeight: 30

    function refresh() {
        if (keyRow.wallpaperBin === "") return
        if (keyStatusProcess.running) keyStatusProcess.running = false
        keyStatusProcess.command = [keyRow.wallpaperBin, "wallhaven", "key", "--status"]
        keyStatusProcess.running = true
    }

    function save(key) {
        var value = String(key || "").trim()
        if (value === "") {
            keyRow.status = "invalid"
            return
        }
        keyRow.pendingKey = value
        keySetProcess.command = [keyRow.wallpaperBin, "wallhaven", "key", "--set"]
        keySetProcess.running = true
    }

    function clear() {
        if (keyClearProcess.running) return
        keyClearProcess.command = [keyRow.wallpaperBin, "wallhaven", "key", "--clear"]
        keyClearProcess.running = true
    }

    onWallpaperBinChanged: if (keyRow.visible) keyRow.refresh()
    onVisibleChanged: if (keyRow.visible) keyRow.refresh()

    RowLayout {
        anchors.fill: parent
        spacing: Theme.spacingSm

        Text {
            Layout.fillWidth: true
            text: keyRow.status === "configured"
                ? "Wallhaven API key configured"
                : (keyRow.status === "not-configured"
                    ? "No API key (anonymous search, 45 req/min)"
                    : (keyRow.status === "invalid"
                        ? "Enter a wallhaven API key first"
                        : "Wallhaven API key status unknown"))
            color: keyRow.status === "invalid" ? Theme.error : Theme.textMuted
            font.family: Theme.fontFamilyProse
            font.pixelSize: Theme.fontSizeXs
            elide: Text.ElideRight
        }

        TextField {
            id: keyField
            Layout.preferredWidth: 220
            Layout.preferredHeight: 28
            placeholderText: "New API key (stored 0600)"
            echoMode: TextInput.Password
            font.family: Theme.fontFamilyResolved
            font.pixelSize: Theme.fontSizeXs
            color: Theme.inputText
            placeholderTextColor: Theme.inputPlaceholder
            selectionColor: Theme.inputSelection
            background: Rectangle {
                color: Theme.inputBg
                border.color: keyField.activeFocus
                    ? Theme.inputBorderFocused
                    : Theme.inputBorder
                border.width: Theme.borderWidthDefault
                radius: Theme.radiusSm
            }
            onAccepted: {
                keyRow.save(keyField.text)
                keyField.text = ""
            }
        }

        AureliaActionButton {
            compact: true
            label: "Save key"
            enabled: keyField.text !== ""
            onTriggered: {
                keyRow.save(keyField.text)
                keyField.text = ""
            }
        }

        AureliaActionButton {
            compact: true
            label: "Clear key"
            visible: keyRow.status === "configured"
            onTriggered: keyRow.clear()
        }
    }

    Process {
        id: keyStatusProcess
        command: []
        stdout: StdioCollector { id: keyStatusOutput }
        stderr: StdioCollector { id: keyStatusError }
        onExited: function(code) {
            if (code !== 0) {
                keyRow.status = "unknown"
                return
            }
            var value = String(keyStatusOutput.text || "").trim()
            keyRow.status = value === "configured" ? "configured" : "not-configured"
        }
    }

    Process {
        id: keySetProcess
        command: []
        stdinEnabled: true
        stdout: StdioCollector { id: keySetOutput }
        stderr: StdioCollector { id: keySetError }
        onStarted: {
            write(keyRow.pendingKey + "\n")
            keyRow.pendingKey = ""
            stdinEnabled = false
        }
        onExited: function(code) {
            if (code !== 0) {
                keyRow.status = "unknown"
                return
            }
            keyRow.refresh()
            keyRow.changed()
        }
    }

    Process {
        id: keyClearProcess
        command: []
        stdout: StdioCollector { id: keyClearOutput }
        stderr: StdioCollector { id: keyClearError }
        onExited: function(code) {
            if (code !== 0) {
                keyRow.status = "unknown"
                return
            }
            keyRow.refresh()
            keyRow.changed()
        }
    }
}
