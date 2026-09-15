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
            if (display && display.focused) return Model.resolutionChoices(display)
        }
        return []
    }
    readonly property var refreshValues: {
        for (var i = 0; i < displays.length; i++) {
            var display = displays[i]
            if (display && display.focused) return Model.refreshChoices(display)
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
    property bool scaleExpanded: false
    property bool resolutionExpanded: false
    property bool refreshExpanded: false
    property bool displayManagementExpanded: false
    property bool advancedOpen: false
    property bool identifyingDisplay: false
    property string dropdownKind: ""
    property var dropdownModel: []
    property var dropdownAnchorItem: null

    // The display panel follows the light, spacious control-card language of
    // the reference UI. These tokens intentionally stay local to this panel:
    // the rest of the shell remains theme-owned while this hardware surface
    // keeps a predictable presentation across desktop themes.
    readonly property color displayCard: Theme.popups.background
    readonly property color displayInk: Theme.popups.text
    readonly property color displaySecondary: Theme.textSecondary
    readonly property color displayMuted: Theme.textMuted
    readonly property color displayDivider: Theme.border
    readonly property color displayControl: Theme.surface
    readonly property color displayControlBorder: Theme.border
    readonly property color displayTrack: Theme.border
    readonly property color displayAccent: Theme.accent
    readonly property color displayOnAccent: Theme.bgBase
    readonly property color displayKnob: Theme.text
    readonly property color displayOff: Theme.surfaceElevated
    readonly property string displayFont: Theme.fontFamilyProse
    readonly property real displayScale: Math.max(0.68, Math.min(1.0, root.popupWidth / 565.0)) * Theme.fontScale

    function ui(value) {
        return Math.max(1, Math.round(Number(value) * root.displayScale))
    }

    function activeDisplay() {
        for (var i = 0; i < root.displays.length; i++) {
            if (root.displays[i] && root.displays[i].focused) return root.displays[i]
        }
        return root.displays.length > 0 ? root.displays[0] : null
    }

    function numberLabel(value) {
        var number = Number(value)
        if (!isFinite(number) || number <= 0) return ""
        return String(Math.round(number * 100) / 100)
    }

    function resolutionLabel(display) {
        if (!display || Number(display.width) <= 0 || Number(display.height) <= 0)
            return "Resolution unavailable"
        return Number(display.width) + "×" + Number(display.height)
    }

    function refreshLabel(display) {
        if (!display || Number(display.refreshRate) <= 0) return "Refresh rate unavailable"
        return numberLabel(display.refreshRate) + " Hz"
    }

    function displaySubtitle(display) {
        if (!display) return "No display detected"
        var parts = []
        if (String(display.name || "") !== "") parts.push(String(display.name))
        var resolution = resolutionLabel(display)
        if (resolution !== "Resolution unavailable") parts.push(resolution)
        var refresh = refreshLabel(display)
        if (refresh !== "Refresh rate unavailable") parts.push(refresh)
        if (display.focused === true) parts.push("Primary")
        return parts.join(" · ")
    }

    function resolutionOptionLabel(mode) {
        if (!mode) return "Resolution unavailable"
        if (mode.label) return mode.label
        var label = Number(mode.width) + " × " + Number(mode.height)
        if (mode.mode !== root.currentResolution && Number(mode.refresh) > 0)
            label += " @ " + numberLabel(mode.refresh) + " Hz"
        else if (mode.mode === root.currentResolution)
            label += " (Native)"
        return label
    }

    function currentScaleLabel() {
        var index = root.activeScaleIndex()
        if (index >= 0 && index < root.scaleValues.length)
            return root.effectiveScale(root.scaleValues[index]) + "×"
        return root.monitorScale !== "" ? root.monitorScale + "×" : "—"
    }

    function currentResolutionIndex() {
        for (var i = 0; i < root.resolutionValues.length; i++) {
            if (root.resolutionValues[i].mode === root.currentResolution) return i
        }
        return root.resolutionValues.length > 0 ? 0 : -1
    }

    function currentResolutionMode() {
        var index = root.currentResolutionIndex()
        return index >= 0 ? root.resolutionValues[index] : null
    }

    function toggleScaleSelector() {
        root.toggleDropdown("scale", scaleCombo, root.scaleValues)
    }

    function toggleResolutionSelector() {
        root.toggleDropdown("resolution", resolutionCombo, root.resolutionValues)
    }

    function toggleRefreshSelector() {
        root.toggleDropdown("refresh", refreshCombo, root.refreshValues)
    }

    function toggleDropdown(kind, anchor, model) {
        keyScope.forceActiveFocus()
        if (dropdownPopup.visible && root.dropdownKind === kind) {
            dropdownPopup.close()
            return
        }
        root.dropdownKind = kind
        root.dropdownAnchorItem = anchor
        root.dropdownModel = model || []
        root.cursorActive = true
        root.focusSection = kind === "scale" ? "scale" : "resolution"
        root.scaleExpanded = kind === "scale"
        root.resolutionExpanded = kind === "resolution"
        root.refreshExpanded = kind === "refresh"
        dropdownPopup.open()
    }

    function selectDropdown(index, value) {
        if (root.dropdownKind === "scale") {
            root.setScale(String(value || ""))
        } else if (root.dropdownKind === "resolution" || root.dropdownKind === "refresh") {
            root.setResolution(value && value.mode ? value.mode : "")
        }
        dropdownPopup.close()
    }

    function dropdownLabel(value) {
        if (root.dropdownKind === "scale") return root.effectiveScale(value) + "×"
        if (value && value.label) return value.label
        return String(value || "")
    }

    function dropdownSelected(value, index) {
        if (root.dropdownKind === "scale") return root.activeScaleIndex() === index
        return !!value && value.mode === root.currentResolution
    }

    function adaptiveSyncEnabled() {
        var display = root.activeDisplay()
        return !!display && display.vrr === true
    }

    function identifyDisplay() {
        if (!root.activeDisplay()) return
        dropdownPopup.close()
        root.identifyingDisplay = true
        identifyTimer.restart()
        root.refresh()
    }

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
    contentPadding: root.ui(28)
    popupWidth: 380
    popupHeight: 720
    fitHeightToContent: true
    contentSizingItem: root.advancedOpen ? advancedLoader.item : contentColumn
    minPopupHeight: 220
    maxPopupHeight: root.screenH > 0 ? Math.max(220, root.screenH - root.margin * 2) : 720
    panelBackground: root.displayCard
    panelBorder: "transparent"
    panelBorderWidth: 0
    panelRadius: root.ui(15)
    cardVisible: !root.identifyingDisplay
    overlayComponent: Component {
        Item {
            anchors.fill: parent
            visible: root.identifyingDisplay

            Text {
                anchors.centerIn: parent
                width: parent.width - root.ui(48)
                text: root.activeDisplay() && root.activeDisplay().name
                    ? String(root.activeDisplay().name) : "Display"
                color: root.displayInk
                font.family: root.displayFont
                font.pixelSize: root.ui(150)
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                style: Text.Outline
                styleColor: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: root.ui(72)
                text: root.activeDisplay()
                    ? root.resolutionLabel(root.activeDisplay()) + " · " + root.refreshLabel(root.activeDisplay())
                    : "No display detected"
                color: root.displaySecondary
                font.family: root.displayFont
                font.pixelSize: root.ui(28)
                horizontalAlignment: Text.AlignHCenter
                style: Text.Outline
                styleColor: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: root.identifyingDisplay = false
            }
        }
    }
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
        scaleExpanded = false
        resolutionExpanded = false
        refreshExpanded = false
        displayManagementExpanded = false
        advancedOpen = false
        identifyingDisplay = false
        dropdownPopup.close()
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
        } else if (focusSection === "scale") {
            scaleExpanded = !scaleExpanded
        } else if (focusSection === "resolution" && selectedIndex >= 0 && selectedIndex < resolutionValues.length) {
            setResolution(resolutionValues[selectedIndex].mode)
        } else if (focusSection === "resolution") {
            resolutionExpanded = !resolutionExpanded
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

        Timer {
            id: identifyTimer
            interval: 3000
            repeat: false
            onTriggered: root.identifyingDisplay = false
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
    onScaleValuesChanged: clampCursor()
    onResolutionValuesChanged: clampCursor()
    onVisibleSectionsChanged: clampCursor()
    onBackendRootChanged: root.refresh()
    onAdvancedOpenChanged: {
        if (advancedLoader.item) advancedLoader.item.display = root.activeDisplay()
        if (root.advancedOpen) {
            root.scaleExpanded = false
            root.resolutionExpanded = false
        }
    }
    onDisplaysChanged: {
        clampCursor()
        if (advancedLoader.item) advancedLoader.item.display = root.activeDisplay()
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: root.shown

        Keys.onPressed: function(event) { root.handleKey(event) }

        ScrollView {
            id: scrollView
            anchors.fill: parent
            clip: true
            visible: !root.advancedOpen
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                id: contentColumn
                width: scrollView.availableWidth
                spacing: 0

                Item {
                    width: parent.width
                    height: root.ui(116)

                    DisplayIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: root.ui(3)
                        anchors.top: parent.top
                        anchors.topMargin: root.ui(18)
                        width: root.ui(54)
                        height: root.ui(54)
                        kind: "monitor"
                        color: root.displayInk
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: root.ui(94)
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: root.ui(8)
                        spacing: root.ui(3)

                        Text {
                            width: parent.width
                            text: "Display"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(28)
                            font.weight: Font.Bold
                        }

                        Text {
                            width: parent.width
                            text: root.displaySubtitle(root.activeDisplay())
                            color: root.displaySecondary
                            font.family: root.displayFont
                            font.pixelSize: root.ui(18)
                            elide: Text.ElideRight
                        }
                    }

                }

                Rectangle {
                    width: parent.width
                    height: root.ui(1)
                    color: root.displayDivider
                }

                Item { width: parent.width; height: root.ui(29) }

                Item {
                    width: parent.width
                    height: root.ui(86)
                    visible: true

                    RowLayout {
                        anchors.fill: parent
                        spacing: root.ui(16)

                        DisplayIcon {
                            Layout.preferredWidth: root.ui(42)
                            Layout.preferredHeight: root.ui(42)
                            kind: "brightness"
                            color: root.displayInk
                        }

                        Text {
                            Layout.preferredWidth: root.ui(124)
                            text: "Brightness"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(20)
                        }

                        Slider {
                            id: brightnessSlider
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.ui(36)
                            from: 1
                            to: 100
                            stepSize: 1
                            value: root.brightnessPercent
                            enabled: root.brightnessAvailable
                            onMoved: root.previewBrightness(value)
                            onPressedChanged: if (!pressed) root.setBrightness(value)

                            background: Rectangle {
                                x: brightnessSlider.leftPadding
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                width: brightnessSlider.availableWidth
                                height: root.ui(6)
                                radius: height / 2
                                color: root.displayTrack

                                Rectangle {
                                    width: brightnessSlider.visualPosition * parent.width
                                    height: parent.height
                                    radius: height / 2
                                    color: root.displayAccent
                                }
                            }

                            handle: Rectangle {
                                x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                width: root.ui(29)
                                height: width
                                radius: width / 2
                                color: root.displayKnob
                                border.color: root.displayControlBorder
                                border.width: root.ui(1)
                            }
                        }

                        Text {
                            Layout.preferredWidth: root.ui(54)
                            text: root.brightnessAvailable ? Math.round(brightnessSlider.value) + "%" : "Fixed"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(20)
                            horizontalAlignment: Text.AlignRight
                        }

                        HoverHandler {
                            onHoveredChanged: if (hovered && !root.reflowingText) {
                                root.cursorActive = true
                                root.focusSection = "brightness"
                                root.selectedIndex = -1
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: root.ui(86)

                    RowLayout {
                        anchors.fill: parent
                        spacing: root.ui(16)

                        Text {
                            Layout.preferredWidth: root.ui(42)
                            text: "Aᴬ"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(30)
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            Layout.preferredWidth: root.ui(124)
                            text: "Text size"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(20)
                        }

                        Slider {
                            id: textSizeSlider
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.ui(36)
                            from: 0
                            to: root.textSizeStops.length - 1
                            stepSize: 1
                            value: root.currentTextIndex()
                            onMoved: root.textSizePreviewIndex = Math.round(value)
                            onPressedChanged: if (!pressed) root.setTextSize(root.textSizeStops[Math.round(value)])

                            background: Rectangle {
                                x: textSizeSlider.leftPadding
                                y: textSizeSlider.topPadding + textSizeSlider.availableHeight / 2 - height / 2
                                width: textSizeSlider.availableWidth
                                height: root.ui(6)
                                radius: height / 2
                                color: root.displayTrack

                                Rectangle {
                                    width: textSizeSlider.visualPosition * parent.width
                                    height: parent.height
                                    radius: height / 2
                                    color: root.displayAccent
                                }
                            }

                            handle: Rectangle {
                                x: textSizeSlider.leftPadding + textSizeSlider.visualPosition * (textSizeSlider.availableWidth - width)
                                y: textSizeSlider.topPadding + textSizeSlider.availableHeight / 2 - height / 2
                                width: root.ui(29)
                                height: width
                                radius: width / 2
                                color: root.displayKnob
                                border.color: root.displayControlBorder
                                border.width: root.ui(1)
                            }
                        }

                        Text {
                            Layout.preferredWidth: root.ui(54)
                            text: root.displayedTextSize() + " px"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(20)
                            horizontalAlignment: Text.AlignRight
                        }

                        HoverHandler {
                            onHoveredChanged: if (hovered && !root.reflowingText) {
                                root.cursorActive = true
                                root.focusSection = "textsize"
                                root.selectedIndex = -1
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: root.ui(86)

                    RowLayout {
                        anchors.fill: parent
                        spacing: root.ui(16)

                        DisplayIcon {
                            Layout.preferredWidth: root.ui(42)
                            Layout.preferredHeight: root.ui(42)
                            kind: "monitor"
                            color: root.displayInk
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Scale (UI)"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(20)
                        }

                        Rectangle {
                            id: scaleCombo
                            Layout.preferredWidth: root.ui(282)
                            Layout.minimumWidth: root.ui(190)
                            Layout.preferredHeight: root.ui(52)
                            radius: root.ui(12)
                            color: root.displayControl
                            border.color: root.scaleExpanded || (root.cursorActive && root.focusSection === "scale")
                                ? root.displayAccent : root.displayControlBorder
                            border.width: root.ui(1)

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: root.ui(18)
                                anchors.right: chevron.left
                                anchors.rightMargin: root.ui(8)
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.currentScaleLabel()
                                color: root.displayInk
                                font.family: root.displayFont
                                font.pixelSize: root.ui(20)
                                elide: Text.ElideRight
                            }

                            Text {
                                id: chevron
                                anchors.right: parent.right
                                anchors.rightMargin: root.ui(15)
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.scaleExpanded ? "⌃" : "⌄"
                                color: root.displayInk
                                font.family: root.displayFont
                                font.pixelSize: root.ui(25)
                            }

                            MouseArea {
                                anchors.fill: parent
                                z: 10
                                hoverEnabled: true
                                preventStealing: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    root.cursorActive = true
                                    root.focusSection = "scale"
                                    root.selectedIndex = -1
                                }
                                onClicked: root.toggleScaleSelector()
                            }
                        }
                    }

                    MouseArea {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.ui(282)
                        height: root.ui(52)
                        z: 100
                        hoverEnabled: true
                        preventStealing: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleScaleSelector()
                    }
                }

                Item {
                    width: parent.width
                    height: root.resolutionValues.length > 0 ? root.ui(86) : 0
                    visible: root.resolutionValues.length > 0

                    RowLayout {
                        anchors.fill: parent
                        spacing: root.ui(16)

                        DisplayIcon {
                            Layout.preferredWidth: root.ui(42)
                            Layout.preferredHeight: root.ui(42)
                            kind: "monitor"
                            color: root.displayInk
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Resolution"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(20)
                        }

                        Rectangle {
                            id: resolutionCombo
                            Layout.preferredWidth: root.ui(282)
                            Layout.minimumWidth: root.ui(190)
                            Layout.preferredHeight: root.ui(52)
                            radius: root.ui(12)
                            color: root.displayControl
                            border.color: root.resolutionExpanded || (root.cursorActive && root.focusSection === "resolution")
                                ? root.displayAccent : root.displayControlBorder
                            border.width: root.ui(1)

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: root.ui(18)
                                anchors.right: resolutionChevron.left
                                anchors.rightMargin: root.ui(8)
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.resolutionOptionLabel(root.currentResolutionMode())
                                color: root.displayInk
                                font.family: root.displayFont
                                font.pixelSize: root.ui(18)
                                elide: Text.ElideRight
                            }

                            Text {
                                id: resolutionChevron
                                anchors.right: parent.right
                                anchors.rightMargin: root.ui(15)
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.resolutionExpanded ? "⌃" : "⌄"
                                color: root.displayInk
                                font.family: root.displayFont
                                font.pixelSize: root.ui(25)
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    root.cursorActive = true
                                    root.focusSection = "resolution"
                                    root.selectedIndex = root.currentResolutionIndex()
                                }
                                onClicked: root.toggleResolutionSelector()
                            }
                        }
                    }

                    MouseArea {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.ui(282)
                        height: root.ui(52)
                        z: 100
                        hoverEnabled: true
                        preventStealing: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleResolutionSelector()
                    }
                }

                Item {
                    width: parent.width
                    height: root.activeDisplay() !== null ? root.ui(86) : 0
                    visible: root.activeDisplay() !== null

                    RowLayout {
                        anchors.fill: parent
                        spacing: root.ui(16)

                        DisplayIcon {
                            Layout.preferredWidth: root.ui(42)
                            Layout.preferredHeight: root.ui(42)
                            kind: "refresh"
                            color: root.displayInk
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Refresh rate"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(20)
                        }

                        Rectangle {
                            id: refreshCombo
                            Layout.preferredWidth: root.ui(282)
                            Layout.minimumWidth: root.ui(190)
                            Layout.preferredHeight: root.ui(52)
                            radius: root.ui(12)
                            color: root.displayControl
                            border.color: root.refreshExpanded || (root.cursorActive && root.focusSection === "resolution")
                                ? root.displayAccent : root.displayControlBorder
                            border.width: root.ui(1)

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: root.ui(18)
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.refreshLabel(root.activeDisplay())
                                color: root.displayInk
                                font.family: root.displayFont
                                font.pixelSize: root.ui(18)
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: root.ui(15)
                                anchors.verticalCenter: parent.verticalCenter
                                text: "⌄"
                                color: root.displayInk
                                font.family: root.displayFont
                                font.pixelSize: root.ui(25)
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleRefreshSelector()
                            }
                        }
                    }
                }

                Item { width: parent.width; height: root.ui(26) }

                Rectangle {
                    width: parent.width
                    height: root.ui(1)
                    color: root.displayDivider
                }

                Item { width: parent.width; height: root.ui(22) }

                Item {
                    width: parent.width
                    height: root.ui(76)

                    RowLayout {
                        anchors.fill: parent
                        spacing: root.ui(16)

                        DisplayIcon {
                            Layout.preferredWidth: root.ui(42)
                            Layout.preferredHeight: root.ui(42)
                            kind: "adaptive"
                            color: root.displayInk
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Adaptive sync (VRR)"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(20)
                        }

                        Rectangle {
                            Layout.preferredWidth: root.ui(64)
                            Layout.preferredHeight: root.ui(36)
                            radius: height / 2
                            color: root.adaptiveSyncEnabled() ? root.displayAccent : root.displayOff

                            Rectangle {
                                width: root.ui(28)
                                height: width
                                radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                x: root.adaptiveSyncEnabled()
                                    ? parent.width - width - root.ui(4) : root.ui(4)
                                color: root.displayKnob
                            }
                        }
                    }
                }

                Item { width: parent.width; height: root.ui(22) }

                Rectangle {
                    width: parent.width
                    height: root.ui(1)
                    color: root.displayDivider
                }

                Item { width: parent.width; height: root.ui(20) }

                Item {
                    width: parent.width
                    height: root.ui(76)

                    RowLayout {
                        anchors.fill: parent
                        spacing: root.ui(16)

                        DisplayIcon {
                            Layout.preferredWidth: root.ui(42)
                            Layout.preferredHeight: root.ui(42)
                            kind: "gear"
                            color: root.displayInk
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Advanced"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(20)
                        }

                        Text {
                            Layout.preferredWidth: root.ui(26)
                            text: "›"
                            color: root.displayInk
                            font.family: root.displayFont
                            font.pixelSize: root.ui(34)
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            root.cursorActive = true
                        }
                        onClicked: root.advancedOpen = true
                    }
                }

                Item { width: parent.width; height: root.ui(22) }

                Rectangle {
                    width: parent.width
                    height: root.ui(1)
                    color: root.displayDivider
                }

                Item {
                    width: parent.width
                    height: root.ui(94)

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: root.ui(16)

                                DisplayIcon {
                                    Layout.preferredWidth: root.ui(34)
                                    Layout.preferredHeight: root.ui(34)
                                    kind: "identify"
                                    color: root.identifyingDisplay ? root.displayAccent : root.displayInk
                                }

                                Text {
                                    text: root.identifyingDisplay ? "Identifying…" : "Identify display"
                                    color: root.identifyingDisplay ? root.displayAccent : root.displayInk
                                    font.family: root.displayFont
                                    font.pixelSize: root.ui(19)
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.identifyDisplay()
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: root.ui(1)
                            Layout.preferredHeight: root.ui(50)
                            color: root.displayDivider
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: root.ui(16)

                                DisplayIcon {
                                    Layout.preferredWidth: root.ui(34)
                                    Layout.preferredHeight: root.ui(34)
                                    kind: "arrange"
                                    color: root.displayInk
                                }

                                Text {
                                    text: "Arrange displays"
                                    color: root.displayInk
                                    font.family: root.displayFont
                                    font.pixelSize: root.ui(19)
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.displayManagementExpanded = !root.displayManagementExpanded
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: root.displayManagementExpanded
                    height: visible ? implicitHeight : 0
                    spacing: root.ui(10)

                    Text {
                        width: parent.width
                        text: "ADDITIONAL DISPLAYS"
                        color: root.displaySecondary
                        font.family: root.displayFont
                        font.pixelSize: root.ui(13)
                        font.weight: Font.Bold
                        font.letterSpacing: root.ui(1)
                    }

                    Text {
                        width: parent.width
                        visible: root.displays.length <= 1
                        text: "No additional displays detected"
                        color: root.displayMuted
                        font.family: root.displayFont
                        font.pixelSize: root.ui(15)
                    }

                    Repeater {
                        model: root.displays

                        Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: root.ui(56)
                            radius: root.ui(12)
                            opacity: modelData.enabled || root.enabledDisplayCount > 1 ? 1 : 0.5
                            color: modelData.focused ? root.displayAccent : root.displayControl
                            border.color: modelData.focused ? root.displayAccent : root.displayControlBorder
                            border.width: root.ui(1)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: root.ui(16)
                                anchors.rightMargin: root.ui(16)
                                spacing: root.ui(12)

                                DisplayIcon {
                                    Layout.preferredWidth: root.ui(28)
                                    Layout.preferredHeight: root.ui(28)
                                    kind: "monitor"
                                    color: modelData.focused ? root.displayOnAccent : root.displaySecondary
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: String(modelData.name || "Display") +
                                        (modelData.width > 0 && modelData.height > 0
                                            ? " · " + modelData.width + "×" + modelData.height
                                            : "")
                                    color: modelData.focused ? root.displayOnAccent : root.displayInk
                                    font.family: root.displayFont
                                    font.pixelSize: root.ui(17)
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: modelData.enabled ? "✓" : ""
                                    color: modelData.focused ? root.displayOnAccent : root.displayAccent
                                    font.family: root.displayFont
                                    font.pixelSize: root.ui(20)
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: modelData.enabled && root.enabledDisplayCount <= 1
                                    ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onEntered: {
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

                Item { width: parent.width; height: root.ui(10) }
            }
        }

        ScrollView {
            id: advancedScrollView
            anchors.fill: parent
            clip: true
            visible: root.advancedOpen
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Loader {
                id: advancedLoader
                width: advancedScrollView.availableWidth
                height: item ? item.implicitHeight : 0
                source: Qt.resolvedUrl("DisplayAdvancedContent.qml")
                onLoaded: {
                    item.scaleFactor = root.displayScale
                    item.display = root.activeDisplay()
                }
            }
        }

        Connections {
            target: advancedLoader.item
            function onBackRequested() { root.advancedOpen = false }
        }

        Popup {
            id: dropdownPopup
            parent: keyScope
            modal: false
            focus: true
            padding: root.ui(5)
            width: root.ui(282)
            height: Math.min(
                root.ui(4 * 44) + padding * 2 + root.ui(6) * 3,
                Math.max(root.ui(54), root.dropdownModel.length * root.ui(44) + padding * 2 +
                    Math.max(0, root.dropdownModel.length - 1) * root.ui(6)))
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            x: root.dropdownAnchorItem && typeof root.dropdownAnchorItem.mapToItem === "function"
                ? root.dropdownAnchorItem.mapToItem(keyScope, 0, 0).x : 0
            y: root.dropdownAnchorItem && typeof root.dropdownAnchorItem.mapToItem === "function"
                ? root.dropdownAnchorItem.mapToItem(keyScope, 0, root.dropdownAnchorItem.height).y + root.ui(5) : 0

            background: Rectangle {
                radius: root.ui(12)
                color: root.displayCard
                border.color: root.displayAccent
                border.width: root.ui(1)
            }

            contentItem: ListView {
                id: dropdownList
                clip: true
                model: root.dropdownModel
                spacing: root.ui(6)
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: dropdownList.width
                    height: root.ui(44)
                    radius: root.ui(9)
                    color: root.dropdownSelected(modelData, index)
                        ? root.displayAccent : root.displayControl
                    border.color: root.dropdownSelected(modelData, index)
                        ? root.displayAccent : root.displayControlBorder
                    border.width: root.ui(1)

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: root.ui(14)
                        anchors.right: parent.right
                        anchors.rightMargin: root.ui(12)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.dropdownLabel(modelData)
                        color: root.dropdownSelected(modelData, index) ? root.displayOnAccent : root.displayInk
                        font.family: root.displayFont
                        font.pixelSize: root.ui(16)
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDropdown(index, modelData)
                    }
                }
            }

            onClosed: {
                root.dropdownKind = ""
                root.dropdownAnchorItem = null
                root.dropdownModel = []
                root.scaleExpanded = false
                root.resolutionExpanded = false
                root.refreshExpanded = false
            }
        }

        Rectangle {
            visible: root.identifyingDisplay && !root.advancedOpen
            anchors.centerIn: parent
            width: Math.min(parent.width - root.ui(24), root.ui(300))
            height: root.ui(148)
            z: 200
            radius: root.ui(16)
            color: root.displayAccent
            border.color: root.displayOnAccent
            border.width: root.ui(1)

            Column {
                anchors.centerIn: parent
                spacing: root.ui(5)

                DisplayIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.ui(34)
                    height: root.ui(34)
                    kind: "identify"
                    color: root.displayOnAccent
                }

                Text {
                    width: root.ui(260)
                    text: "DISPLAY IDENTIFICATION"
                    color: root.displayOnAccent
                    font.family: root.displayFont
                    font.pixelSize: root.ui(13)
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: root.ui(260)
                    text: root.activeDisplay() && root.activeDisplay().name
                        ? String(root.activeDisplay().name) : "Display"
                    color: root.displayOnAccent
                    font.family: root.displayFont
                    font.pixelSize: root.ui(20)
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: root.ui(260)
                    text: root.activeDisplay()
                        ? root.resolutionLabel(root.activeDisplay()) + " · " + root.refreshLabel(root.activeDisplay())
                        : "No display detected"
                    color: root.displayOnAccent
                    font.family: root.displayFont
                    font.pixelSize: root.ui(14)
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: root.identifyingDisplay = false
            }
        }
    }
}
