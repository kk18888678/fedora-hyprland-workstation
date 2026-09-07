import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../../theme"

PanelWindow {
    id: panelRoot

    property string backendBin: ""
    property var processEnvironment: ({})
    property var anchorWindow: null
    property string statusMessage: ""
    property string statusKind: "info"
    property string captureStage: "menu"
    property string pendingGeometry: ""
    property string pendingWindowLabel: ""
    property int delaySeconds: 3
    property int barSize: 26
    property bool showPointer: false
    property bool quickCapture: false
    property var windows: []
    property real selectionStartX: 0
    property real selectionStartY: 0
    property real selectionEndX: 0
    property real selectionEndY: 0
    property bool selectionDragging: false

    signal captureRequested(string mode, int delay, string geometry, bool pointer)

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "aurelia-screenshot"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    implicitWidth: 0
    implicitHeight: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: false

    readonly property bool barAtBottom: anchorWindow && anchorWindow.position === "bottom"

    function resetMenu() {
        captureStage = "menu"
        pendingGeometry = ""
        pendingWindowLabel = ""
        windows = []
        statusMessage = ""
        statusKind = "info"
        delaySeconds = 3
        showPointer = false
        quickCapture = false
    }

    function open(payloadJson) {
        resetMenu()
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot)
        visible = true
        try {
            var payload = JSON.parse(payloadJson || "{}")
            if (payload.mode && payload.mode !== "menu") {
                capture(String(payload.mode), Number(payload.delay || delaySeconds), String(payload.geometry || ""))
            }
        } catch (e) {
            statusMessage = "Invalid screenshot request."
            statusKind = "error"
        }
    }

    function close() {
        if (windowsProcess.running) windowsProcess.running = false
        visible = false
        if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(panelRoot)
    }

    function closeForPopoutSwitch() { close() }

    function capture(mode, delay, geometry) {
        if (captureProcess.running) return
        var safeDelay = Number.isFinite(delay) ? Math.max(0, Math.min(30, Math.floor(delay))) : 0
        statusMessage = safeDelay > 0 ? "Waiting " + safeDelay + " seconds..." : "Capturing..."
        statusKind = "info"
        captureStage = "capturing"
        visible = false
        if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(panelRoot)
        captureRequested(mode, safeDelay, geometry || "", showPointer)
    }

    function quickRegion() {
        resetMenu()
        quickCapture = true
        startRegionSelection()
    }

    function capturePayload(payloadJson) {
        open(payloadJson)
    }

    function startRegionSelection() {
        if (!backendBin || backendBin.length === 0) {
            visible = true
            captureStage = "menu"
            statusMessage = "Screenshot backend is unavailable."
            statusKind = "error"
            return
        }
        captureStage = "region-selecting"
        pendingGeometry = ""
        statusMessage = "Select a region..."
        statusKind = "info"
        console.info("[SCREENSHOT] region selection started backend=" + backendBin)
        selectionStartX = 0
        selectionStartY = 0
        selectionEndX = 0
        selectionEndY = 0
        selectionDragging = false
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot)
        visible = true
    }

    function startWindowSelection() {
        if (windowsProcess.running) return
        if (!backendBin || backendBin.length === 0) {
            captureStage = "menu"
            statusMessage = "Screenshot backend is unavailable."
            statusKind = "error"
            return
        }
        captureStage = "window-list"
        statusMessage = "Loading open windows..."
        statusKind = "info"
        console.info("[SCREENSHOT] window list requested backend=" + backendBin)
        if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot)
        windows = []
        windowsProcess.command = [backendBin, "windows"]
        windowsProcess.running = true
    }

    function captureWindow(windowData) {
        var at = windowData.at || [0, 0]
        var size = windowData.size || [0, 0]
        if (at.length < 2 || size.length < 2 || Number(size[0]) <= 0 || Number(size[1]) <= 0) {
            statusMessage = "The selected window has no capturable geometry."
            statusKind = "error"
            return
        }
        pendingWindowLabel = windowData.title || windowData.class || "Window"
        var geometry = String(at[0]) + "," + String(at[1]) + " " + String(size[0]) + "x" + String(size[1])
        captureStage = "menu"
        capture("window", delaySeconds, geometry)
    }

    function capturePendingRegion(delay) {
        if (!pendingGeometry) return
        var geometry = pendingGeometry
        captureStage = "menu"
        capture("region", delay, geometry)
    }

    function captureCompleted(code, output, errorOutput, durationMs) {
        captureStage = "menu"
        var result = String(output || "").trim()
        var errorText = String(errorOutput || "").trim()
        if (code === 0) {
            visible = false
            if (anchorWindow && typeof anchorWindow.releasePopout === "function") anchorWindow.releasePopout(panelRoot)
            statusMessage = result !== "" ? ("Screenshot saved and copied (" + durationMs + " ms).") : ("Screenshot captured (" + durationMs + " ms).")
            statusKind = "success"
        } else {
            if (anchorWindow && typeof anchorWindow.requestPopout === "function") anchorWindow.requestPopout(panelRoot)
            visible = true
            statusMessage = errorText || ("Capture failed (status " + code + ").")
            statusKind = "error"
        }
    }

    Process {
        id: windowsProcess
        command: []
        environment: panelRoot.processEnvironment
        stdout: StdioCollector { id: windowsStdout }
        stderr: StdioCollector { id: windowsStderr }

        onExited: function(code) {
            if (code === 0) {
                try {
                    windows = JSON.parse(windowsStdout.text || "[]")
                    captureStage = "window-list"
                    statusMessage = windows.length > 0 ? "Select an open window." : "No open windows found."
                    statusKind = "info"
                } catch (e) {
                    windows = []
                    captureStage = "menu"
                    statusMessage = "Could not read open windows."
                    statusKind = "error"
                }
            } else {
                captureStage = "menu"
                statusMessage = windowsStderr.text.trim() || "Could not query open windows."
                statusKind = "error"
            }
        }
    }

    Rectangle {
        id: selectionOverlay
        anchors.fill: parent
        z: 3
        visible: panelRoot.captureStage === "region-selecting"
        color: "#33ffffff"
        focus: visible

        Text {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Theme.spacingXl
            text: "Drag to select a region · Esc to cancel"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.weight: Theme.fontWeightMedium
        }

        Rectangle {
            id: selectionRect
            x: Math.min(panelRoot.selectionStartX, panelRoot.selectionEndX)
            y: Math.min(panelRoot.selectionStartY, panelRoot.selectionEndY)
            width: Math.abs(panelRoot.selectionEndX - panelRoot.selectionStartX)
            height: Math.abs(panelRoot.selectionEndY - panelRoot.selectionStartY)
            color: "#22ffffff"
            border.color: "#ffffffff"
            border.width: Theme.borderWidthFocus
            visible: panelRoot.selectionDragging
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            onPressed: function(mouse) {
                mouse.accepted = true
                panelRoot.selectionStartX = mouse.x
                panelRoot.selectionStartY = mouse.y
                panelRoot.selectionEndX = mouse.x
                panelRoot.selectionEndY = mouse.y
                panelRoot.selectionDragging = true
            }
            onPositionChanged: function(mouse) {
                if (!panelRoot.selectionDragging) return
                mouse.accepted = true
                panelRoot.selectionEndX = mouse.x
                panelRoot.selectionEndY = mouse.y
            }
            onReleased: function(mouse) {
                mouse.accepted = true
                if (!panelRoot.selectionDragging) return
                panelRoot.selectionEndX = mouse.x
                panelRoot.selectionEndY = mouse.y
                panelRoot.selectionDragging = false

                var left = Math.floor(Math.min(panelRoot.selectionStartX, panelRoot.selectionEndX))
                var top = Math.floor(Math.min(panelRoot.selectionStartY, panelRoot.selectionEndY))
                var width = Math.floor(Math.abs(panelRoot.selectionEndX - panelRoot.selectionStartX))
                var height = Math.floor(Math.abs(panelRoot.selectionEndY - panelRoot.selectionStartY))
                if (width < 4 || height < 4) {
                    panelRoot.statusMessage = "Selection is too small."
                    panelRoot.statusKind = "error"
                    return
                }

                var originX = 0
                var originY = 0
                if (panelRoot.screen) {
                    var screenX = Number(panelRoot.screen.virtualX)
                    var screenY = Number(panelRoot.screen.virtualY)
                    if (Number.isFinite(screenX)) originX = Math.floor(screenX)
                    if (Number.isFinite(screenY)) originY = Math.floor(screenY)
                }
                panelRoot.pendingGeometry = String(originX + left) + "," + String(originY + top) + " " + String(width) + "x" + String(height)
                console.info("[SCREENSHOT] native region geometry=" + panelRoot.pendingGeometry)
                if (panelRoot.quickCapture) {
                    var quickGeometry = panelRoot.pendingGeometry
                    panelRoot.quickCapture = false
                    panelRoot.capture("region", 0, quickGeometry)
                    return
                }
                panelRoot.captureStage = "region-ready"
                panelRoot.statusMessage = "Region selected. Capture it now or choose again."
                panelRoot.statusKind = "success"
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        enabled: panelRoot.captureStage !== "region-selecting"
        acceptedButtons: Qt.LeftButton
        onClicked: function(mouse) {
            mouse.accepted = true
            panelRoot.close()
        }
    }

    Rectangle {
        id: card
        width: Math.min(parent.width - Theme.spacingXxl * 2, 560)
        height: panelRoot.captureStage === "window-list" ? 560 : 480
        anchors.right: parent.right
        anchors.top: barAtBottom ? undefined : parent.top
        anchors.bottom: barAtBottom ? parent.bottom : undefined
        anchors.topMargin: barAtBottom ? 0 : panelRoot.barSize + Theme.spacingLg
        anchors.bottomMargin: barAtBottom ? panelRoot.barSize + Theme.spacingLg : 0
        anchors.rightMargin: Theme.spacingLg
        z: 1
        visible: panelRoot.captureStage !== "region-selecting"
        radius: Theme.radiusLg
        color: Theme.bgBase
        border.color: Theme.border
        border.width: Theme.borderWidthDefault
        focus: panelRoot.visible && panelRoot.captureStage !== "region-selecting"

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: function(mouse) { mouse.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingXl
            spacing: Theme.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: panelRoot.captureStage === "window-list" ? "Select window" : (panelRoot.captureStage === "region-ready" ? "Region selected" : "Screenshots")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXl
                    font.weight: Theme.fontWeightBold
                }
                Text {
                    text: "ESC"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }
            }

            Text {
                Layout.fillWidth: true
                text: panelRoot.captureStage === "window-list" ? "Choose an open application window to capture." : (panelRoot.captureStage === "region-ready" ? "The selection is ready. Capture it using the current delay and pointer settings." : "Choose a capture area. Screenshots are saved to Pictures and copied to the clipboard.")
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                wrapMode: Text.WordWrap
            }

            GridLayout {
                visible: panelRoot.captureStage === "menu"
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Theme.spacingSm
                columnSpacing: Theme.spacingSm

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: Theme.radiusMd
                    color: screenHover.hovered ? Theme.selection : Theme.surface
                    Text { anchors.centerIn: parent; text: "Screen"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                    HoverHandler { id: screenHover }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) { mouse.accepted = true; panelRoot.capture("full", 0, "") }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: Theme.radiusMd
                    color: windowHover.hovered ? Theme.selection : Theme.surface
                    Text { anchors.centerIn: parent; text: "Window"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                    HoverHandler { id: windowHover }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) { mouse.accepted = true; panelRoot.startWindowSelection() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: Theme.radiusMd
                    color: regionHover.hovered ? Theme.selection : Theme.surface
                    Text { anchors.centerIn: parent; text: "Selection (Region)"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                    HoverHandler { id: regionHover }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) { mouse.accepted = true; panelRoot.startRegionSelection() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: Theme.radiusMd
                    color: delayHover.hovered ? Theme.selection : Theme.surface
                    Text { anchors.centerIn: parent; text: "Full screen + delay"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                    HoverHandler { id: delayHover }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) { mouse.accepted = true; panelRoot.capture("full", panelRoot.delaySeconds, "") }
                    }
                }
            }

            ListView {
                visible: panelRoot.captureStage === "window-list"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.spacingSm
                model: panelRoot.windows

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 52
                    radius: Theme.radiusMd
                    color: windowItemHover.hovered ? Theme.selection : Theme.surface
                    HoverHandler { id: windowItemHover }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingMd
                        anchors.rightMargin: Theme.spacingMd
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: modelData.title || modelData.class || "Window"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.class || ""
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            panelRoot.captureWindow(modelData)
                        }
                    }
                }
            }

            RowLayout {
                visible: panelRoot.captureStage === "region-ready" || panelRoot.captureStage === "window-list"
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: panelRoot.captureStage === "region-ready" ? "Delay and pointer settings apply on capture." : "Click a window to capture it."
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }
                Text {
                    text: "← Back"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.spacingSm
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            panelRoot.captureStage = "menu"
                            panelRoot.statusMessage = ""
                        }
                    }
                }
            }

            RowLayout {
                visible: panelRoot.captureStage === "region-ready"
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: Theme.radiusMd
                    color: Theme.accent
                    Text { anchors.centerIn: parent; text: "Take Screenshot"; color: Theme.bgBase; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) { mouse.accepted = true; panelRoot.capturePendingRegion(0) }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: Theme.radiusMd
                    color: Theme.selection
                    Text { anchors.centerIn: parent; text: "Take Screenshot with Delay"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.weight: Theme.fontWeightMedium }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) { mouse.accepted = true; panelRoot.capturePendingRegion(panelRoot.delaySeconds) }
                    }
                }
            }

            RowLayout {
                visible: panelRoot.captureStage === "menu" || panelRoot.captureStage === "region-ready"
                Layout.fillWidth: true
                spacing: Theme.spacingMd

                Text {
                    text: "Delay (seconds)"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                TextInput {
                    id: delayInput
                    Layout.preferredWidth: 62
                    Layout.preferredHeight: 32
                    text: String(panelRoot.delaySeconds)
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    selectByMouse: true
                    validator: IntValidator { bottom: 0; top: 30 }

                    Rectangle {
                        anchors.fill: parent
                        z: -1
                        radius: Theme.radiusSm
                        color: Theme.surface
                        border.color: delayInput.activeFocus ? Theme.borderActive : Theme.border
                        border.width: Theme.borderWidthDefault
                    }

                    onEditingFinished: {
                        var next = Number(text)
                        if (!Number.isFinite(next)) next = 3
                        panelRoot.delaySeconds = Math.max(0, Math.min(30, Math.floor(next)))
                        text = String(panelRoot.delaySeconds)
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Show pointer"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }

                Rectangle {
                    Layout.preferredWidth: 54
                    Layout.preferredHeight: 28
                    radius: 14
                    color: panelRoot.showPointer ? Theme.accent : Theme.surface
                    border.color: panelRoot.showPointer ? Theme.accent : Theme.border
                    border.width: Theme.borderWidthDefault

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        x: panelRoot.showPointer ? parent.width - width - 4 : 4
                        color: panelRoot.showPointer ? Theme.bgBase : Theme.textMuted
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            panelRoot.showPointer = !panelRoot.showPointer
                        }
                    }
                }

                Text {
                    text: panelRoot.showPointer ? "On" : "Off"
                    color: panelRoot.showPointer ? Theme.accent : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }
            }

            Text {
                Layout.fillWidth: true
                text: panelRoot.statusMessage
                color: panelRoot.statusKind === "error" ? Theme.error : (panelRoot.statusKind === "success" ? Theme.success : Theme.textMuted)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                wrapMode: Text.Wrap
                visible: text.length > 0
            }
        }

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                panelRoot.close()
                event.accepted = true
            }
        }
    }
}
