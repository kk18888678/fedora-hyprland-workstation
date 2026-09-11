import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../ui"
import "../../theme"
import "Model.js" as Model

AureliaKeyboardPanel {
    id: root

    readonly property string sourceBinRoot: {
        var configuredRoot = Quickshell.env("AURELIA_SHELL_ROOT") || ""
        if (configuredRoot.charAt(0) === "/") return configuredRoot + "/bin"
        return decodeURIComponent(String(Qt.resolvedUrl("../../bin")).replace(/^file:\/\//, ""))
    }
    property string backendRoot: sourceBinRoot

    property int brightnessPercent: 0
    property int pendingBrightnessPercent: 0
    property bool brightnessSetQueued: false
    property bool brightnessAvailable: false
    property string focusedMonitor: ""
    property string monitorScale: ""
    property var displays: []
    property int enabledDisplayCount: 0
    property real wheelAccumulator: 0

    readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
    readonly property var scaleValues: {
        for (var i = 0; i < displays.length; i++) {
            var display = displays[i]
            if (display && display.focused)
                return Model.availableScales(scalePresets, display.width, display.height)
        }
        return scalePresets
    }
    readonly property var resolutionValues: {
        for (var i = 0; i < displays.length; i++) {
            var display = displays[i]
            if (display && display.focused) return Model.resolutionModes(display)
        }
        return []
    }
    readonly property string currentResolution: {
        for (var i = 0; i < displays.length; i++) {
            var display = displays[i]
            if (display && display.focused) return Model.currentMode(display)
        }
        return ""
    }
    readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
    readonly property var visibleSections: {
        var result = []
        if (brightnessAvailable) result.push("brightness")
        result.push("textsize")
        result.push("scale")
        if (resolutionValues.length > 0) result.push("resolution")
        if (displays.length > 1) result.push("monitors")
        return result
    }

    property string focusSection: "textsize"
    property int selectedIndex: -1
    property bool cursorActive: false
    property int textSizePreviewIndex: -1
    property bool reflowingText: false

    readonly property string stateBin: backendRoot + "/aurelia-monitor-state"
    readonly property string brightnessBin: backendRoot + "/aurelia-brightness-display"
    readonly property string scaleBin: backendRoot + "/aurelia-hyprland-monitor-scaling"
    readonly property string resolutionBin: backendRoot + "/aurelia-hyprland-monitor-resolution"
    readonly property string textSizeBin: backendRoot + "/aurelia-display-text-size"
    readonly property var processEnvironment: ({
        "PATH": root.backendRoot + ":/usr/local/bin:/usr/bin:/bin" +
            (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : ""),
        "HOME": Quickshell.env("HOME") || "",
        "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || "",
        "HYPRLAND_INSTANCE_SIGNATURE": Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    })

    bar: null
    anchorItem: null
    ownerId: "aurelia.monitor"
    contentPadding: Theme.popupPadding
    popupWidth: 380
    popupHeight: 560
    fitHeightToContent: true
    contentSizingItem: contentColumn
    minPopupHeight: 220
    maxPopupHeight: 560
    focusTarget: keyScope
    shown: false

    function open(payloadJson) {
        refresh()
        shown = true
        cursorActive = false
        if (brightnessAvailable) {
            focusSection = "brightness"
            selectedIndex = -1
        } else {
            focusSection = "textsize"
            selectedIndex = -1
        }
    }

    function close() { shown = false }
    function closeForPopoutSwitch() { close() }

    function clampCursor() {
        var sections = visibleSections
        if (!sections || sections.length === 0) return
        if (sections.indexOf(focusSection) < 0) {
            focusSection = sections[0]
            selectedIndex = sectionFirstIndex(focusSection)
            return
        }

        if (focusSection === "brightness" || focusSection === "textsize") {
            selectedIndex = -1
            return
        }
        var count = sectionCount(focusSection)
        if (count <= 0) {
            focusSection = sections[0]
            selectedIndex = sectionFirstIndex(focusSection)
            return
        }
        selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex))
    }

    function sectionCount(section) {
        if (section === "scale") return scaleValues.length
        if (section === "resolution") return resolutionValues.length
        if (section === "monitors") return displays.length
        return 0
    }

    function sectionIsSingleRow(section) {
        return section === "brightness" || section === "textsize"
    }

    function sectionFirstIndex(section) {
        return sectionIsSingleRow(section) ? -1 : 0
    }

    function moveCursor(delta) {
        var sections = visibleSections
        if (!sections.length) return
        var sectionIndex = sections.indexOf(focusSection)
        if (sectionIndex < 0) {
            focusSection = sections[0]
            selectedIndex = sectionFirstIndex(focusSection)
            return
        }

        var single = sectionIsSingleRow(focusSection)
        var max = single ? 0 : sectionCount(focusSection) - 1
        if (delta > 0) {
            if (!single && selectedIndex < max) {
                selectedIndex++
                return
            }
            if (sectionIndex < sections.length - 1) {
                focusSection = sections[sectionIndex + 1]
                selectedIndex = sectionFirstIndex(focusSection)
            }
        } else {
            if (!single && selectedIndex > 0) {
                selectedIndex--
                return
            }
            if (sectionIndex > 0) {
                focusSection = sections[sectionIndex - 1]
                selectedIndex = sectionIsSingleRow(focusSection)
                    ? -1
                    : sectionCount(focusSection) - 1
            }
        }
    }

    function moveCursorHorizontal(delta) {
        if (focusSection === "brightness") {
            adjustBrightness(delta * 5)
            return
        }
        if (focusSection === "textsize") {
            adjustTextSize(delta)
            return
        }
        if (focusSection !== "scale" || scaleValues.length === 0) return
        selectedIndex = Math.max(0, Math.min(scaleValues.length - 1, selectedIndex + delta))
    }

    function activateCursor() {
        if (focusSection === "scale" && selectedIndex >= 0 && selectedIndex < scaleValues.length) {
            setScale(scaleValues[selectedIndex])
        } else if (focusSection === "resolution" && selectedIndex >= 0 && selectedIndex < resolutionValues.length) {
            setResolution(resolutionValues[selectedIndex].mode)
        } else if (focusSection === "monitors" && selectedIndex >= 0 && selectedIndex < displays.length) {
            var display = displays[selectedIndex]
            if (display) toggleDisplay(display.name, display.enabled === true)
        }
    }

    function handleKey(event) {
        var key = event.key
        var text = String(event.text || "").toLowerCase()
        var vertical = key === Qt.Key_Down || key === Qt.Key_J ? 1 :
            (key === Qt.Key_Up || key === Qt.Key_K ? -1 : 0)
        var horizontal = key === Qt.Key_Right || key === Qt.Key_L ? 1 :
            (key === Qt.Key_Left || key === Qt.Key_H ? -1 : 0)

        if (key === Qt.Key_Escape) {
            close()
            event.accepted = true
        } else if (vertical !== 0 || horizontal !== 0 || text === "j" || text === "k" || text === "h" || text === "l") {
            if (!cursorActive) {
                cursorActive = true
            } else if (vertical !== 0) {
                moveCursor(vertical)
            } else if (horizontal !== 0) {
                moveCursorHorizontal(horizontal)
            }
            event.accepted = true
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (cursorActive) activateCursor()
            event.accepted = true
        }
    }

    function adjustBrightness(delta) {
        if (!brightnessAvailable) return
        setBrightness(brightnessPercent + Number(delta || 0))
    }

    function previewBrightness(value) {
        brightnessPercent = Model.clampBrightness(value)
    }

    function setBrightness(value) {
        var percent = Model.clampBrightness(value)
        brightnessPercent = percent
        pendingBrightnessPercent = percent
        if (brightnessSetProcess.running) {
            brightnessSetQueued = true
            return
        }
        brightnessSetQueued = false
        var command = ["/bin/bash", brightnessBin, "--no-osd"]
        if (focusedMonitor !== "") command.push("--monitor", focusedMonitor)
        command.push(percent + "%")
        brightnessSetProcess.command = command
        brightnessSetProcess.running = true
    }

    function brightnessName(value) { return Model.brightnessName(value) }

    function updateDisplays(raw) {
        var parsed = Model.parseDisplays(raw)
        displays = parsed.displays
        enabledDisplayCount = parsed.enabledDisplayCount
        clampCursor()
    }

    function refresh() {
        if (!stateProcess.running) stateProcess.running = true
    }

    function activeScaleIndex() {
        for (var i = 0; i < displays.length; i++) {
            var display = displays[i]
            if (display && display.focused)
                return Model.matchingScaleIndex(scaleValues, monitorScale, display.width, display.height)
        }
        return -1
    }

    function effectiveScale(value) {
        for (var i = 0; i < displays.length; i++) {
            var display = displays[i]
            if (display && display.focused)
                return Model.cleanScale(value, display.width, display.height) || Model.normalizeScale(value)
        }
        return Model.normalizeScale(value)
    }

    function setScale(value) {
        var normalized = Model.normalizeScale(value)
        if (normalized === "") return
        if (scaleProcess.running) {
            pendingScale = normalized
            return
        }
        scaleProcess.command = ["/bin/bash", scaleBin, normalized]
        scaleProcess.running = true
    }

    property string pendingScale: ""
    property string pendingResolution: ""

    function setResolution(value) {
        var normalized = Model.normalizedMode(value)
        if (normalized === "") return
        if (resolutionProcess.running) {
            pendingResolution = normalized
            return
        }
        resolutionProcess.command = ["/bin/bash", resolutionBin, normalized]
        resolutionProcess.running = true
    }

    function nearestTextStop(value) {
        var number = Number(value)
        if (!isFinite(number)) number = 12
        var best = 0
        var distance = Infinity
        for (var i = 0; i < textSizeStops.length; i++) {
            var nextDistance = Math.abs(textSizeStops[i] - number)
            if (nextDistance < distance) {
                best = i
                distance = nextDistance
            }
        }
        return best
    }

    function currentTextIndex() {
        if (textSizePreviewIndex >= 0) return textSizePreviewIndex
        return nearestTextStop(Theme.fontBaseSize)
    }

    function displayedTextSize() {
        if (textSizePreviewIndex >= 0) return textSizeStops[textSizePreviewIndex]
        return Theme.fontBaseSize
    }

    function setTextSize(value) {
        var number = Math.round(Number(value))
        if (!isFinite(number) || number < 9 || number > 20) return
        textSizePreviewIndex = nearestTextStop(number)
        textSizeProcess.command = ["/bin/bash", textSizeBin, String(number)]
        textSizeProcess.running = true
        reflowingText = true
        reflowTimer.restart()
    }

    function adjustTextSize(delta) {
        var index = Math.max(0, Math.min(textSizeStops.length - 1, currentTextIndex() + delta))
        setTextSize(textSizeStops[index])
    }

    function toggleDisplay(name, enabled) {
        var monitorName = String(name || "")
        if (!/^[A-Za-z0-9._-]+$/.test(monitorName)) return
        if (enabled && enabledDisplayCount <= 1) return
        if (displayActionProcess.running) return
        displayActionProcess.command = ["/usr/bin/timeout", "--kill-after=1s", "3s", "/usr/bin/hyprctl", "keyword", "monitor",
            monitorName + (enabled ? ",disable" : ",preferred,auto,auto")]
        displayActionProcess.running = true
    }

    Item {
        id: backendObjects
        width: 0
        height: 0
        visible: false

        Timer {
            id: refreshTimer
            interval: 5000
            repeat: true
            running: root.shown
            onTriggered: root.refresh()
        }

        Timer {
            id: reflowTimer
            interval: 300
            repeat: false
            onTriggered: root.reflowingText = false
        }

        Process {
            id: stateProcess
            command: ["/bin/bash", root.stateBin]
            environment: root.processEnvironment
            stdout: StdioCollector {
                waitForEnd: true
                onStreamFinished: {
                    var lines = String(text || "").split("\n")
                    var brightness = String(lines[0] || "").trim()
                    var parsedBrightness = parseInt(brightness, 10)
                    root.brightnessAvailable = brightness !== "unavailable" && brightness !== "" && !isNaN(parsedBrightness)
                    root.brightnessPercent = root.brightnessAvailable ? Model.clampBrightness(parsedBrightness) : 0
                    root.focusedMonitor = String(lines[5] || "").trim()
                    root.monitorScale = Model.normalizeScale(String(lines[6] || "").trim())
                    root.updateDisplays(String(lines[7] || "[]").trim())
                }
            }
            stderr: StdioCollector { id: stateStderr; waitForEnd: true }
            onExited: function(code) {
                if (code !== 0) console.warn("[DISPLAY] state_failed code=" + code + " error=" + stateStderr.text.trim())
                root.clampCursor()
            }
        }

        Process {
            id: brightnessSetProcess
            command: []
            environment: root.processEnvironment
            stdout: StdioCollector { waitForEnd: true }
            stderr: StdioCollector { waitForEnd: true }
            onRunningChanged: {
                if (running || !root.brightnessSetQueued) return
                root.setBrightness(root.pendingBrightnessPercent)
            }
            onExited: function(code) {
                if (code !== 0) console.warn("[DISPLAY] brightness_set_failed code=" + code)
            }
        }

        Process {
            id: scaleProcess
            command: []
            environment: root.processEnvironment
            stdout: StdioCollector { waitForEnd: true }
            stderr: StdioCollector { id: scaleStderr; waitForEnd: true }
            onRunningChanged: {
                if (running || root.pendingScale === "") return
                var next = root.pendingScale
                root.pendingScale = ""
                root.setScale(next)
            }
            onExited: function(code) {
                if (code !== 0) console.warn("[DISPLAY] scale_set_failed code=" + code + " error=" + scaleStderr.text.trim())
                root.refresh()
            }
        }

        Process {
            id: resolutionProcess
            command: []
            environment: root.processEnvironment
            stdout: StdioCollector { waitForEnd: true }
            stderr: StdioCollector { id: resolutionStderr; waitForEnd: true }
            onRunningChanged: {
                if (running || root.pendingResolution === "") return
                var next = root.pendingResolution
                root.pendingResolution = ""
                root.setResolution(next)
            }
            onExited: function(code) {
                if (code !== 0) console.warn("[DISPLAY] resolution_set_failed code=" + code + " error=" + resolutionStderr.text.trim())
                root.refresh()
            }
        }

        Process {
            id: displayActionProcess
            command: []
            stdout: StdioCollector { waitForEnd: true }
            stderr: StdioCollector { waitForEnd: true }
            onExited: function(code) {
                if (code !== 0) console.warn("[DISPLAY] monitor_action_failed code=" + code)
                root.refresh()
            }
        }

        Process {
            id: textSizeProcess
            command: []
            environment: root.processEnvironment
            stdout: StdioCollector { waitForEnd: true }
            stderr: StdioCollector { waitForEnd: true }
            onExited: function(code) {
                if (code !== 0) {
                    root.textSizePreviewIndex = -1
                    console.warn("[DISPLAY] text_size_failed code=" + code)
                }
                if (Theme && typeof Theme.reloadDisplaySettings === "function") Theme.reloadDisplaySettings()
            }
        }

        Connections {
            target: Theme
            function onFontBaseSizeChanged() {
                root.reflowingText = true
                reflowTimer.restart()
                if (root.textSizePreviewIndex >= 0 &&
                    root.nearestTextStop(Theme.fontBaseSize) === root.textSizePreviewIndex)
                    root.textSizePreviewIndex = -1
            }
        }
    }

    Component.onCompleted: {
        console.info("[DISPLAY] backend_root=" + root.backendRoot)
        refresh()
    }
    onBrightnessAvailableChanged: clampCursor()
    onDisplaysChanged: clampCursor()
    onScaleValuesChanged: clampCursor()
    onResolutionValuesChanged: clampCursor()
    onVisibleSectionsChanged: clampCursor()
    onBackendRootChanged: Qt.callLater(function() { root.refresh() })

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: root.shown

        Keys.onPressed: function(event) { root.handleKey(event) }

        ScrollView {
            id: scrollView
            anchors.fill: parent
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                id: contentColumn
                width: scrollView.availableWidth
                spacing: Theme.spacingMd

                Item {
                    width: parent.width
                    height: 54

                    RowLayout {
                        anchors.fill: parent
                        spacing: Theme.spacingMd

                        Text {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            text: root.displays.length > 1 ? "󰍺" : "󰍹"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 42
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs

                            Text {
                                Layout.fillWidth: true
                                text: "Display"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXl
                                font.weight: Theme.fontWeightBold
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.brightnessAvailable
                                    ? root.brightnessName(brightnessSlider.value).toUpperCase()
                                    : "FIXED BRIGHTNESS"
                                color: Theme.textSecondary
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                font.weight: Theme.fontWeightBold
                                font.letterSpacing: 1
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.currentResolution !== ""
                                    ? "CURRENT " + root.currentResolution
                                    : "RESOLUTION UNAVAILABLE"
                                color: Theme.textSubtle
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    visible: root.brightnessAvailable
                    color: Theme.border
                    opacity: 0.6
                }

                Column {
                    width: parent.width
                    visible: root.brightnessAvailable
                    spacing: Theme.spacingXs

                    RowLayout {
                        width: parent.width
                        height: 22

                        Text {
                            Layout.fillWidth: true
                            text: "BRIGHTNESS"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 0.8
                        }

                        Text {
                            text: Math.round(brightnessSlider.value) + "%"
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 42
                        radius: Theme.radiusSm
                        color: root.cursorActive && root.focusSection === "brightness"
                            ? Theme.selection
                            : Theme.surface
                        border.color: root.cursorActive && root.focusSection === "brightness"
                            ? Theme.borderActive
                            : Theme.border
                        border.width: Theme.borderWidthDefault

                        Slider {
                            id: brightnessSlider
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSm
                            anchors.rightMargin: Theme.spacingSm
                            from: 1
                            to: 100
                            stepSize: 1
                            value: root.brightnessPercent
                            enabled: root.brightnessAvailable
                            onMoved: root.previewBrightness(value)
                            onPressedChanged: if (!pressed) root.setBrightness(value)
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            hoverEnabled: true
                            onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
                                root.cursorActive = true
                                root.focusSection = "brightness"
                                root.selectedIndex = -1
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.border
                    opacity: 0.6
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXs

                    RowLayout {
                        width: parent.width
                        height: 22

                        Text {
                            Layout.fillWidth: true
                            text: "TEXT SIZE"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 0.8
                        }

                        Text {
                            text: root.displayedTextSize() + "px"
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 42
                        radius: Theme.radiusSm
                        color: root.cursorActive && root.focusSection === "textsize"
                            ? Theme.selection
                            : Theme.surface
                        border.color: root.cursorActive && root.focusSection === "textsize"
                            ? Theme.borderActive
                            : Theme.border
                        border.width: Theme.borderWidthDefault

                        Slider {
                            id: textSizeSlider
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingSm
                            anchors.rightMargin: Theme.spacingSm
                            from: 0
                            to: root.textSizeStops.length - 1
                            stepSize: 1
                            value: root.currentTextIndex()
                            onMoved: root.textSizePreviewIndex = Math.round(value)
                            onPressedChanged: if (!pressed) root.setTextSize(root.textSizeStops[Math.round(value)])
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            hoverEnabled: true
                            onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
                                root.cursorActive = true
                                root.focusSection = "textsize"
                                root.selectedIndex = -1
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.border
                    opacity: 0.6
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingSm

                    RowLayout {
                        width: parent.width
                        height: 22

                        Text {
                            Layout.fillWidth: true
                            text: "SCALE"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 0.8
                        }

                        Text {
                            text: root.focusedMonitor
                            visible: root.focusedMonitor !== "" && root.enabledDisplayCount > 1
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            elide: Text.ElideLeft
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingXs

                        Repeater {
                            model: root.scaleValues

                            Rectangle {
                                required property string modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                radius: Theme.radiusSm
                                color: root.cursorActive && root.focusSection === "scale" && root.selectedIndex === index
                                    ? Theme.selectionActive
                                    : (root.activeScaleIndex() === index ? Theme.selection : Theme.surface)
                                border.color: root.activeScaleIndex() === index ? Theme.borderActive : Theme.border
                                border.width: Theme.borderWidthDefault

                                Text {
                                    anchors.centerIn: parent
                                    text: root.effectiveScale(modelData) + "x"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    font.weight: Theme.fontWeightMedium
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
                                        root.cursorActive = true
                                        root.focusSection = "scale"
                                        root.selectedIndex = index
                                    }
                                    onClicked: root.setScale(modelData)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    visible: root.resolutionValues.length > 0
                    color: Theme.border
                    opacity: 0.6
                }

                Column {
                    width: parent.width
                    visible: root.resolutionValues.length > 0
                    spacing: Theme.spacingXs

                    RowLayout {
                        width: parent.width
                        height: 22

                        Text {
                            Layout.fillWidth: true
                            text: "RESOLUTION"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 0.8
                        }

                        Text {
                            text: root.currentResolution
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                        }
                    }

                    Repeater {
                        model: root.resolutionValues

                        Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 34
                            radius: Theme.radiusSm
                            color: root.cursorActive && root.focusSection === "resolution" && root.selectedIndex === index
                                ? Theme.selectionActive
                                : (modelData.mode === root.currentResolution ? Theme.selection : Theme.surface)
                            border.color: modelData.mode === root.currentResolution ? Theme.borderActive : Theme.border
                            border.width: Theme.borderWidthDefault

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingSm
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.weight: Theme.fontWeightMedium
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
                                    root.cursorActive = true
                                    root.focusSection = "resolution"
                                    root.selectedIndex = index
                                }
                                onClicked: root.setResolution(modelData.mode)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    visible: root.displays.length > 1
                    color: Theme.border
                    opacity: 0.6
                }

                Column {
                    width: parent.width
                    visible: root.displays.length > 1
                    spacing: Theme.spacingXs

                    Text {
                        width: parent.width
                        text: "DISPLAYS"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                        font.letterSpacing: 0.8
                    }

                    Repeater {
                        model: root.displays

                        Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 42
                            radius: Theme.radiusSm
                            opacity: modelData.enabled || root.enabledDisplayCount > 1 ? 1 : 0.5
                            color: root.cursorActive && root.focusSection === "monitors" && root.selectedIndex === index
                                ? Theme.selectionActive
                                : (modelData.focused ? Theme.selection : Theme.surface)
                            border.color: modelData.focused ? Theme.borderActive : Theme.border
                            border.width: Theme.borderWidthDefault

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingSm
                                anchors.rightMargin: Theme.spacingSm
                                spacing: Theme.spacingSm

                                Text {
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    text: "󰍹"
                                    color: Theme.textSecondary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 18
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(modelData.name || "Display") +
                                        (modelData.width > 0 && modelData.height > 0
                                            ? " · " + modelData.width + "×" + modelData.height
                                            : "") +
                                        (modelData.focused ? " · focused" : "")
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: modelData.enabled ? "✓" : ""
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeMd
                                    font.weight: Theme.fontWeightBold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: modelData.enabled && root.enabledDisplayCount <= 1
                                    ? Qt.ArrowCursor
                                    : Qt.PointingHandCursor
                                onContainsMouseChanged: if (containsMouse && !root.reflowingText) {
                                    root.cursorActive = true
                                    root.focusSection = "monitors"
                                    root.selectedIndex = index
                                }
                                onClicked: if (!modelData.enabled || root.enabledDisplayCount > 1)
                                    root.toggleDisplay(modelData.name, modelData.enabled === true)
                            }
                        }
                    }
                }

                Item { width: parent.width; height: Theme.spacingXs }
            }
        }
    }
}
