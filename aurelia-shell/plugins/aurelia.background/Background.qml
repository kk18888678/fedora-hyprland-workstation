import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// Resident Aurelia wallpaper service. It owns one background layer per screen
// so wallpaper presence is independent of the focused workspace and survives
// empty/dynamic workspaces. Theme selection remains data-only and is applied
    // through Theme.qml's active state. The wallpaper surface also provides
    // the Omarchy-style background-picker entry point on double-click.
Item {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateHomeOverride: Quickshell.env("XDG_STATE_HOME") || ""
    readonly property string stateHome: stateHomeOverride.charAt(0) === "/"
        ? stateHomeOverride
        : home + "/.local/state"
    readonly property string backgroundStatePath: stateHome + "/aurelia/current/background.path"
    readonly property string legacyNoctaliaStatePath: stateHome + "/noctalia/settings.toml"
    readonly property string configuredWallpaper: Quickshell.env("AURELIA_WALLPAPER") || ""

    property string backgroundPath: ""
    property string displayedBackground: ""
    property string incomingBackground: ""
    property int displayedReloads: 0
    property real transitionProgress: 1
    property bool transitionRunning: false
    property bool initialResolutionPending: true
    property bool reloadRequested: false
    property bool stateFileSettled: false
    property bool legacyFileSettled: false
    property string lastError: ""

    readonly property bool hasBackground: root.displayedBackground !== ""
    readonly property int transitionDuration: 420

    function isVideoPath(value) {
        return /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(String(value || ""))
    }

    function fileUrl(value) {
        var parts = String(value || "").split("/")
        for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
        return "file://" + parts.join("/")
    }

    function normalizePath(value) {
        var path = String(value || "").trim()
        if (path.length >= 2 &&
            ((path.charAt(0) === "\"" && path.charAt(path.length - 1) === "\"") ||
             (path.charAt(0) === "'" && path.charAt(path.length - 1) === "'"))) {
            path = path.substring(1, path.length - 1)
        }
        return path
    }

    function validBackgroundPath(value) {
        var path = root.normalizePath(value)
        return path.charAt(0) === "/" && path !== "/" &&
            path.indexOf("\n") === -1 && path.indexOf("\r") === -1 &&
            /\.(jpg|jpeg|png|gif|bmp|webp|mp4|m4v|mov|webm|mkv|avi)$/i.test(path)
    }

    function legacyBackgroundPath(raw) {
        var lines = String(raw || "").split("\n")
        var inLast = false
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === "[wallpaper.last]") {
                inLast = true
                continue
            }
            if (inLast && line.charAt(0) === "[") break
            if (inLast) {
                var match = line.match(/^path\s*=\s*["']([^"']+)["']/)
                if (match) return root.normalizePath(match[1])
            }
        }
        return ""
    }

    function resolveInitialBackground() {
        if ((!root.initialResolutionPending && !root.reloadRequested) ||
            !root.stateFileSettled || !root.legacyFileSettled) {
            if (!root.stateFileSettled || !root.legacyFileSettled)
                root.scheduleInitialResolution()
            return
        }
        var candidate = ""
        try { candidate = root.normalizePath(backgroundStateFile.text()) } catch (e) {}
        if (!root.validBackgroundPath(candidate)) candidate = root.normalizePath(root.configuredWallpaper)
        if (!root.validBackgroundPath(candidate)) {
            try { candidate = root.legacyBackgroundPath(legacyNoctaliaFile.text()) } catch (e2) { candidate = "" }
        }
        root.initialResolutionPending = false
        root.reloadRequested = false
        if (root.validBackgroundPath(candidate)) root.setBackground(candidate, true)
        else console.info("[BACKGROUND] no wallpaper selected; using themed solid fallback")
    }

    function scheduleInitialResolution() {
        initialResolveTimer.restart()
    }

    function setBackground(path, instant) {
        var next = root.normalizePath(path)
        if (!root.validBackgroundPath(next)) {
            root.lastError = "Background path is invalid or unsupported."
            console.warn("[BACKGROUND] path_invalid")
            return false
        }
        root.lastError = ""
        if (next === root.backgroundPath && !instant) {
            root.displayedReloads += 1
            return true
        }

        root.backgroundPath = next
        transitionFallbackTimer.stop()
        transitionAnimation.stop()
        root.transitionRunning = false

        if (instant || root.displayedBackground === "" ||
            root.isVideoPath(next) || root.isVideoPath(root.displayedBackground)) {
            root.incomingBackground = ""
            root.transitionProgress = 1
            root.displayedBackground = next
            root.displayedReloads += 1
            return true
        }

        root.incomingBackground = next
        root.transitionProgress = 0
        transitionFallbackTimer.restart()
        return true
    }

    function maybeStartTransition() {
        if (root.incomingBackground === "" || root.transitionRunning) return
        root.transitionRunning = true
        transitionAnimation.restart()
    }

    function finishTransition() {
        root.displayedBackground = root.backgroundPath
        root.incomingBackground = ""
        root.transitionProgress = 1
        root.transitionRunning = false
    }

    function reload() {
        root.reloadRequested = true
        root.stateFileSettled = false
        backgroundStateFile.reload()
        root.scheduleInitialResolution()
    }

    function applyTheme() {
        // Palette and wallpaper state are refreshed from the same selector
        // transaction. The background transition then becomes the visual
        // reveal boundary for the newly loaded Aurelia palette.
        Theme.reloadTheme()
        root.reload()
        return "ok"
    }

    IpcHandler {
        target: "aurelia.background"

        function ping(): string { return "ok" }
        function reload(): string {
            root.reload()
            return "ok"
        }
        function set(path: string): string {
            return root.setBackground(path, false) ? "ok" : "invalid"
        }
        function setInstant(path: string): string {
            return root.setBackground(path, true) ? "ok" : "invalid"
        }
        function current(): string { return root.backgroundPath }
    }

    Timer {
        id: initialResolveTimer
        interval: 100
        repeat: false
        onTriggered: root.resolveInitialBackground()
    }

    Timer {
        id: transitionFallbackTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (root.incomingBackground !== "") root.finishTransition()
        }
    }

    NumberAnimation {
        id: transitionAnimation
        target: root
        property: "transitionProgress"
        from: 0
        to: 1
        duration: root.transitionDuration
        easing.type: Easing.InOutCubic
        onFinished: root.finishTransition()
    }

    FileView {
        id: backgroundStateFile
        path: root.backgroundStatePath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.stateFileSettled = true
            root.scheduleInitialResolution()
        }
        onLoadFailed: {
            root.stateFileSettled = true
            root.scheduleInitialResolution()
        }
        onFileChanged: {
            root.reloadRequested = true
            root.stateFileSettled = false
            reload()
            root.scheduleInitialResolution()
        }
    }

    FileView {
        id: legacyNoctaliaFile
        path: root.legacyNoctaliaStatePath
        watchChanges: false
        printErrors: false
        onLoaded: {
            root.legacyFileSettled = true
            root.scheduleInitialResolution()
        }
        onLoadFailed: {
            root.legacyFileSettled = true
            root.scheduleInitialResolution()
        }
    }

    Component.onCompleted: root.scheduleInitialResolution()

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData

            screen: modelData
            visible: true
            color: Theme.bgBase
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            updatesEnabled: true
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "aurelia-background"

            readonly property var hyprlandMonitor: Hyprland.monitorFor(modelData)
            readonly property var visibleWorkspace: hyprlandMonitor ? hyprlandMonitor.activeWorkspace : null
            readonly property bool fullscreenHere: visibleWorkspace ? visibleWorkspace.hasFullscreen : false
            readonly property bool firstScreen: Quickshell.screens.length > 0 &&
                String(Quickshell.screens[0].name || "") === String(modelData.name || "")

            BackgroundMedia {
                id: media
                anchors.fill: parent
                path: root.displayedBackground
                reloads: root.displayedReloads
                playbackEnabled: !panel.fullscreenHere
                audioEnabled: panel.firstScreen
            }

            Image {
                id: incomingFrame
                anchors.fill: parent
                source: root.incomingBackground !== "" && !root.isVideoPath(root.incomingBackground)
                    ? root.fileUrl(root.incomingBackground)
                    : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                mipmap: true
                opacity: root.transitionProgress
                visible: root.incomingBackground !== "" && status === Image.Ready
                onStatusChanged: {
                    if (status === Image.Ready) root.maybeStartTransition()
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onDoubleClicked: function(mouse) {
                    if (root.shell && typeof root.shell.summon === "function")
                        root.shell.summon("aurelia.image-picker", '{"mode":"background"}')
                    mouse.accepted = true
                }
            }
        }
    }
}
