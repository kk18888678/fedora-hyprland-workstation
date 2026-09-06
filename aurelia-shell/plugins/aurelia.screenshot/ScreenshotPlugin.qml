import QtQuick
import Quickshell
import Quickshell.Io
import "./ui"

Item {
    id: pluginRoot

    property string aureliaPath: ""
    property var shell: null
    property var manifest: ({})
    property var pluginRegistry: null
    property int barSize: 32

    readonly property string pluginId: "aurelia.screenshot"
    readonly property string backendBin: aureliaPath !== "" ? aureliaPath + "/bin/aurelia-screenshot" : "/usr/local/bin/aurelia-screenshot"
    readonly property var processEnvironment: {
        var env = {
            "PATH": "/usr/local/bin:/usr/bin:/bin" + (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : ""),
            "HOME": Quickshell.env("HOME") || "",
            "WAYLAND_DISPLAY": Quickshell.env("WAYLAND_DISPLAY") || "",
            "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || "",
            "DISPLAY": Quickshell.env("DISPLAY") || "",
            "HYPRLAND_INSTANCE_SIGNATURE": Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "",
            "XDG_PICTURES_DIR": Quickshell.env("XDG_PICTURES_DIR") || ""
        }
        return env
    }
    property double captureStartedAt: 0

    function open(payloadJson) {
        screenshotPanel.open(payloadJson || "{}")
        return "ok"
    }

    function close() {
        if (captureProcess.running) captureProcess.running = false
        screenshotPanel.close()
        return "ok"
    }

    function toggle(payloadJson) {
        if (screenshotPanel.visible) return close()
        return open(payloadJson || "{}")
    }

    function isVisible() {
        return screenshotPanel.visible
    }

    function capture(payloadJson) {
        screenshotPanel.capturePayload(payloadJson || "{}")
        return "started"
    }

    function quickRegion() {
        screenshotPanel.quickRegion()
        return "started"
    }

    Process {
        id: captureProcess
        command: []
        environment: pluginRoot.processEnvironment
        stdout: StdioCollector { id: captureStdout }
        stderr: StdioCollector { id: captureStderr }

        onExited: function(code) {
            var duration = captureStartedAt > 0 ? (Date.now() - captureStartedAt) : 0
            console.info("[SCREENSHOT] capture.end code=" + code + " duration_ms=" + duration + " path=" + captureStdout.text.trim() + " error=" + captureStderr.text.trim())
            screenshotPanel.captureCompleted(code, captureStdout.text, captureStderr.text, duration)
        }
    }

    Connections {
        target: screenshotPanel
        function onCaptureRequested(mode, delay, geometry, pointer) {
            if (captureProcess.running) return
            var command = [pluginRoot.backendBin, "capture", mode, "--delay", String(delay)]
            command.push(pointer ? "--show-pointer" : "--hide-pointer")
            if (geometry && geometry.length > 0) command.push("--geometry", geometry)
            captureStartedAt = Date.now()
            console.info("[SCREENSHOT] capture.begin mode=" + mode + " delay=" + delay + " geometry=" + geometry + " pointer=" + pointer)
            captureProcess.command = command
            captureProcess.running = true
        }
    }

    ScreenshotPanel {
        id: screenshotPanel
        backendBin: pluginRoot.backendBin
        processEnvironment: pluginRoot.processEnvironment
        barSize: pluginRoot.barSize
    }
}
