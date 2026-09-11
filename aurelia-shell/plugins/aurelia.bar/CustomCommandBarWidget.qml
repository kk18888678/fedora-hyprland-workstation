import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../ui"

// Safe command-output bar module. Unlike Omarchy's shell-evaluated `exec`
// string, Aurelia accepts an argv array and wraps it in a bounded timeout.
Item {
    id: root

    property var bar: null
    property var shell: null
    property var settings: ({})
    property string moduleName: ""
    property string outputText: ""
    property bool commandRunning: false

    readonly property string configuredText: String(root.settings && root.settings.text || "")
    readonly property string tooltipText: String(root.settings && root.settings.tooltip || root.moduleName)
    readonly property int refreshSeconds: {
        var value = Number(root.settings && root.settings.interval)
        return isFinite(value) && value >= 1 ? Math.min(3600, Math.floor(value)) : 30
    }
    readonly property string visibleText: root.outputText !== "" ? root.outputText : root.configuredText

    implicitWidth: Math.min(240, Math.max(24, label.implicitWidth + Theme.spacingMd * 2))
    implicitHeight: root.bar && root.bar.barSize ? root.bar.barSize : Theme.bar.sizeHorizontal

    function validArgv(value) {
        if (!Array.isArray(value) || value.length === 0) return []
        var result = []
        for (var i = 0; i < value.length; i++) {
            var part = String(value[i])
            if (!part || part.indexOf("\n") !== -1 || part.indexOf("\r") !== -1 || part.indexOf("\0") !== -1 || part.indexOf("..") !== -1)
                return []
            if (i === 0 && part.indexOf("/") !== -1 &&
                !part.startsWith("/usr/bin/") && !part.startsWith("/usr/local/bin/") &&
                !part.startsWith("/bin/") && !part.startsWith((Quickshell.env("HOME") || "") + "/.local/bin/")) return []
            result.push(part)
        }
        return result
    }

    function commandArgv() {
        return root.validArgv(root.settings ? root.settings.command : null)
    }

    function actionArgv(name) {
        return root.validArgv(root.settings ? root.settings[name] : null)
    }

    function boundedArgv(argv) {
        if (argv.length === 0) return []
        return ["/usr/bin/timeout", "--kill-after=1s", "10s"].concat(argv)
    }

    function refresh() {
        if (root.commandRunning) return
        var argv = root.commandArgv()
        if (argv.length === 0) return
        root.commandRunning = true
        commandProcess.command = root.boundedArgv(argv)
        commandProcess.running = true
    }

    function runAction(name) {
        var argv = root.actionArgv(name)
        if (argv.length === 0) return
        Quickshell.execDetached(root.boundedArgv(argv))
    }

    Process {
        id: commandProcess
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var value = String(text || "").trim()
                root.outputText = value.length > 160 ? value.substring(0, 160) : value
            }
        }
        onExited: root.commandRunning = false
    }

    Timer {
        interval: root.refreshSeconds * 1000
        repeat: true
        running: root.visible && root.commandArgv().length > 0
        onTriggered: root.refresh()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: hover.hovered ? Theme.controls.hoverFill : "transparent"

        Text {
            id: label
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.spacingSm
            anchors.rightMargin: Theme.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            text: root.visibleText
            color: Theme.bar.foreground
            font.family: Theme.fontFamily
            font.pixelSize: root.bar && root.bar.barTextSize ? root.bar.barTextSize : Theme.bar.text
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        HoverHandler { id: hover }

        AureliaToolTip {
            triggerItem: parent
            hovered: hover.hovered
            text: root.tooltipText
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                if (mouse.button === Qt.RightButton) root.runAction("onRightClick")
                else if (mouse.button === Qt.MiddleButton) root.runAction("onMiddleClick")
                else root.runAction("onClick")
            }
        }
    }

    Component.onCompleted: root.refresh()
}
