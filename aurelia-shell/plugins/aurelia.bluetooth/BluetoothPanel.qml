import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../../ui"
import "../../theme"
import "Model.js" as Model

// Internal popup surface for the Aurelia Bluetooth bar widget. This file is
// loaded by BluetoothBarWidget.qml and is not a standalone plugin entry point;
// the manifest exposes only the bar-widget.
AureliaKeyboardPanel {
    id: root

    property var bluetoothWidget: null
    property var shell: null
    property var manifest: ({})
    property var pluginRegistry: null
    property string backendRoot: ""

    property var pendingActions: ({})
    property bool owesDiscoveryStop: false
    property var pendingAudioOutputDevice: null
    property int pendingAudioOutputAttempts: 0
    property int phraseIndex: 0

    readonly property string sourceBinRoot: decodeURIComponent(
        String(Qt.resolvedUrl("../../bin")).replace(/^file:\/\//, "")
    )
    readonly property string effectiveBackendRoot: root.backendRoot !== ""
        ? root.backendRoot
        : root.sourceBinRoot
    readonly property string powerBin: root.effectiveBackendRoot + "/aurelia-bluetooth-power"
    readonly property string deviceBin: root.effectiveBackendRoot + "/aurelia-bluetooth-device"
    readonly property string audioDefaultBin: root.effectiveBackendRoot + "/aurelia-audio-output-set-default"
    readonly property var processEnvironment: ({
        "PATH": root.effectiveBackendRoot + ":/usr/local/bin:/usr/bin:/bin" +
            (Quickshell.env("PATH") ? ":" + Quickshell.env("PATH") : ""),
        "HOME": Quickshell.env("HOME") || "",
        "XDG_RUNTIME_DIR": Quickshell.env("XDG_RUNTIME_DIR") || ""
    })

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
    readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var deviceGroups: Model.deviceLists(root.devices)
    readonly property var connectedDevices: root.deviceGroups.connected || []
    readonly property var knownDevices: root.deviceGroups.known || []
    readonly property var discoveredDevices: root.deviceGroups.discovered || []
    readonly property var deviceSections: Model.visibleSections(
        root.deviceGroups,
        !!(root.adapter && root.adapter.discovering)
    )

    readonly property string iconName: {
        if (!root.adapter) return "bluetooth"
        if (!root.adapter.enabled) return "bluetooth-disabled"
        if (root.connectedDevices.length > 0) return "bluetooth-active"
        return "bluetooth"
    }
    readonly property var activePhrases: [
        "Untangling wires",
        "Streaming vikings",
        "Pairing mysteries",
        "Herding headsets",
        "Taming radios",
        "Summoning speakers",
        "Wrangling codecs",
        "Polishing packets"
    ]
    readonly property bool rotatingPhrases: !!(root.adapter && root.adapter.enabled)
    readonly property string heroStatusText: {
        if (!root.adapter) return "No adapter"
        if (!root.adapter.enabled) return "Turned Off"
        return root.activePhrases[root.phraseIndex % root.activePhrases.length]
    }

    property string focusSection: "header"
    property int selectedIndex: 0
    property bool actionFocused: false
    property bool cursorActive: false
    property string focusedDeviceAddress: ""

    readonly property bool headerHasCursor: root.cursorActive && root.focusSection === "header"
    readonly property string toggleHint: root.adapter && root.adapter.enabled
        ? "Turn Bluetooth off" : "Turn Bluetooth on"

    bar: null
    anchorItem: null
    ownerId: "aurelia.bluetooth"
    contentPadding: Theme.popupPadding
    popupWidth: 380
    popupHeight: 560
    fitHeightToContent: true
    contentSizingItem: contentColumn
    minPopupHeight: 220
    maxPopupHeight: 560
    focusTarget: keyScope
    shown: false

    function deviceLabel(device) { return Model.deviceLabel(device) }
    function hasHumanName(device) { return Model.hasHumanName(device) }

    function sectionCount(section) {
        if (section === "connected") return root.connectedDevices.length
        if (section === "known") return root.knownDevices.length
        if (section === "discovered") return root.discoveredDevices.length
        return 0
    }

    function sectionVisible(section) {
        if (section === "connected") return root.connectedDevices.length > 0
        if (section === "known") return root.knownDevices.length > 0
        return section === "discovered" && root.adapter && root.adapter.discovering &&
            root.discoveredDevices.length > 0
    }

    function devicesForSection(section) {
        return Model.sectionDevices(root.deviceGroups, section)
    }

    readonly property var scrollRows: {
        var rows = []
        for (var k = 0; k < root.knownDevices.length; k++) {
            rows.push({
                dev: Model.deviceRow(root.knownDevices[k]),
                section: "known",
                indexInSection: k
            })
        }
        if (root.sectionVisible("discovered")) {
            for (var d = 0; d < root.discoveredDevices.length; d++) {
                rows.push({
                    dev: Model.deviceRow(root.discoveredDevices[d]),
                    section: "discovered",
                    indexInSection: d
                })
            }
        }
        return rows
    }

    readonly property var connectedRows: {
        var rows = []
        for (var i = 0; i < root.connectedDevices.length; i++)
            rows.push(Model.deviceRow(root.connectedDevices[i]))
        return rows
    }

    function deviceFor(row) {
        var address = row && row.address ? String(row.address) : ""
        if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(address)) return null
        for (var i = 0; i < root.devices.length; i++) {
            var device = root.devices[i]
            if (device && device.address === address) return device
        }
        return null
    }

    readonly property int scrollRowIndex: {
        if (root.focusSection !== "known" && root.focusSection !== "discovered") return -1
        for (var i = 0; i < root.scrollRows.length; i++) {
            var row = root.scrollRows[i]
            if (row.section === root.focusSection && row.indexInSection === root.selectedIndex) return i
        }
        return -1
    }

    function scrollSectionTitle(index) {
        if (index < 0 || index >= root.scrollRows.length) return ""
        if (index > 0 && root.scrollRows[index - 1].section === root.scrollRows[index].section) return ""
        return root.scrollRows[index].section === "known" ? "PAIRED" : "AVAILABLE"
    }

    function audioSinks() {
        var sinks = []
        for (var i = 0; i < root.pipewireNodes.length; i++) {
            var node = root.pipewireNodes[i]
            if (node && node.isSink && !node.isStream) sinks.push(node)
        }
        return sinks
    }

    function bluetoothAudioSink(device) {
        var sinks = root.audioSinks()
        for (var i = 0; i < sinks.length; i++) {
            if (Model.bluetoothSinkMatchesDevice(sinks[i], device)) return sinks[i]
        }
        return null
    }

    function setDefaultAudioSink(sink) {
        if (!sink) return
        Pipewire.preferredDefaultAudioSink = sink
        if (sink.id !== undefined && sink.name) {
            Quickshell.execDetached([
                root.audioDefaultBin,
                String(sink.id),
                String(sink.name)
            ])
        }
    }

    function scheduleAudioOutputSwitch(device) {
        root.pendingAudioOutputDevice = {
            address: device && device.address ? device.address : "",
            name: device && device.name ? device.name : "",
            deviceName: device && device.deviceName ? device.deviceName : ""
        }
        root.pendingAudioOutputAttempts = 0
        audioSwitchTimer.restart()
    }

    function switchPendingAudioOutput() {
        if (!root.pendingAudioOutputDevice) return
        var sink = root.bluetoothAudioSink(root.pendingAudioOutputDevice)
        if (sink) {
            root.setDefaultAudioSink(sink)
            root.pendingAudioOutputDevice = null
            audioSwitchTimer.stop()
            return
        }
        root.pendingAudioOutputAttempts++
        if (root.pendingAudioOutputAttempts >= 8) {
            root.pendingAudioOutputDevice = null
            return
        }
        audioSwitchTimer.restart()
    }

    function deviceAt(section, index) {
        var list = root.devicesForSection(section)
        return index >= 0 && index < list.length ? list[index] : null
    }

    function pendingAction(address) {
        return Model.pendingAction(root.pendingActions, address)
    }

    function setPendingAction(address, action) {
        if (!address) return
        root.pendingActions = Model.withPendingAction(root.pendingActions, address, action)
        if (action) pendingTimeout.restart()
    }

    function deviceCommand(action, address) {
        if (!/^[a-z]+$/.test(String(action || ""))) return []
        if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(String(address || ""))) return []
        return [root.deviceBin, String(action), String(address)]
    }

    function runDeviceAction(device, action, pending) {
        if (!device || !device.address) return
        var command = root.deviceCommand(action, device.address)
        if (command.length === 0) return
        root.setPendingAction(device.address, pending)
        Quickshell.execDetached(command)
    }

    function connectDevice(device) {
        if (!device || device.connected) return
        if (device.paired || device.bonded || device.trusted)
            root.runDeviceAction(device, "connect", "connecting")
        else
            root.runDeviceAction(device, "pair", "connecting")
    }

    function disconnectDevice(device) {
        if (!device || !device.address || !device.connected) return
        root.setPendingAction(device.address, "disconnecting")
        if (device.disconnect) device.disconnect()
        var command = root.deviceCommand("disconnect", device.address)
        if (command.length > 0) Quickshell.execDetached(command)
    }

    function forgetDevice(device) {
        if (!device || !device.address) return
        root.runDeviceAction(device, "forget", "forgetting")
    }

    function syncPendingActions() {
        var next = Model.cloneMap(root.pendingActions)
        var changed = false
        for (var address in next) {
            var action = next[address]
            var found = null
            for (var i = 0; i < root.devices.length; i++) {
                if (root.devices[i] && root.devices[i].address === address) {
                    found = root.devices[i]
                    break
                }
            }

            var connected = action === "connecting" && found && found.connected
            var disconnected = action === "disconnecting" && found && !found.connected
            var forgotten = action === "forgetting" && (!found ||
                (!found.paired && !found.bonded && !found.trusted))
            if (connected || disconnected || forgotten) {
                if (connected) root.scheduleAudioOutputSwitch(found)
                delete next[address]
                changed = true
            }
        }
        if (changed) root.pendingActions = next
    }

    function moveCursor(delta) {
        var sections = root.deviceSections
        if (root.focusSection === "header") {
            if (delta > 0 && sections.length > 0) {
                root.focusSection = sections[0]
                root.selectedIndex = 0
                root.actionFocused = false
            }
            return
        }
        if (!sections || sections.length === 0) {
            root.focusSection = "header"
            root.actionFocused = false
            return
        }
        var sectionIndex = sections.indexOf(root.focusSection)
        if (sectionIndex < 0) {
            root.focusSection = sections[0]
            root.selectedIndex = 0
            root.actionFocused = false
            return
        }
        var max = root.sectionCount(root.focusSection) - 1
        if (delta > 0) {
            if (root.selectedIndex < max) {
                root.selectedIndex++
                root.actionFocused = false
            } else if (sectionIndex < sections.length - 1) {
                root.focusSection = sections[sectionIndex + 1]
                root.selectedIndex = 0
                root.actionFocused = false
            }
        } else if (root.selectedIndex > 0) {
            root.selectedIndex--
            root.actionFocused = false
        } else if (sectionIndex > 0) {
            root.focusSection = sections[sectionIndex - 1]
            root.selectedIndex = root.sectionCount(root.focusSection) - 1
            root.actionFocused = false
        } else {
            root.focusSection = "header"
            root.actionFocused = false
        }
    }

    function setHeaderCursor() {
        root.cursorActive = true
        root.focusSection = "header"
        root.actionFocused = false
    }

    function moveCursorHorizontal(delta) {
        if (!root.cursorActive) {
            root.cursorActive = true
            return
        }
        if (root.focusSection !== "known" && root.focusSection !== "connected") return
        var device = root.deviceAt(root.focusSection, root.selectedIndex)
        if (!device || !device.address) return
        if (delta > 0) root.actionFocused = true
        else if (delta < 0) root.actionFocused = false
    }

    function activateCursor() {
        if (root.focusSection === "header") {
            root.toggleBluetooth()
            return
        }
        if (root.actionFocused) {
            root.deleteSelected()
            return
        }
        var device = root.deviceAt(root.focusSection, root.selectedIndex)
        if (!device) return
        if (device.connected) root.disconnectDevice(device)
        else root.connectDevice(device)
    }

    function deleteSelected() {
        if (root.focusSection !== "known" && root.focusSection !== "connected") return
        var device = root.deviceAt(root.focusSection, root.selectedIndex)
        if (device) root.forgetDevice(device)
    }

    function handleKey(event) {
        var key = event.key
        var text = String(event.text || "").toLowerCase()
        var vertical = key === Qt.Key_Down || key === Qt.Key_J ? 1 :
            (key === Qt.Key_Up || key === Qt.Key_K ? -1 : 0)
        var horizontal = key === Qt.Key_Right || key === Qt.Key_L ? 1 :
            (key === Qt.Key_Left || key === Qt.Key_H ? -1 : 0)

        if (key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
        } else if (text === "b") {
            root.toggleBluetooth()
            event.accepted = true
        } else if (text === "x" || key === Qt.Key_Delete) {
            if (root.cursorActive) root.deleteSelected()
            event.accepted = true
        } else if (vertical !== 0 || horizontal !== 0) {
            if (!root.cursorActive) root.cursorActive = true
            else if (vertical !== 0) root.moveCursor(vertical)
            else root.moveCursorHorizontal(horizontal)
            event.accepted = true
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (root.cursorActive) root.activateCursor()
            event.accepted = true
        }
    }

    function activateRow(row, section) {
        var device = root.deviceFor(row)
        if (!device) return
        if (device.connected) root.disconnectDevice(device)
        else root.connectDevice(device)
    }

    function secondaryRow(row, section) {
        var device = root.deviceFor(row)
        if (!device) return
        if (device.connected) root.disconnectDevice(device)
        else if (section !== "discovered") root.forgetDevice(device)
    }

    function pointerEntered(section, index) {
        root.cursorActive = true
        root.focusSection = section
        root.selectedIndex = index
        root.actionFocused = false
    }

    function reselectFocusedDevice() {
        if (root.focusedDeviceAddress === "") {
            root.clampCursor()
            return
        }
        var sections = ["connected", "known", "discovered"]
        for (var s = 0; s < sections.length; s++) {
            var section = sections[s]
            if (!root.sectionVisible(section)) continue
            var list = root.devicesForSection(section)
            for (var i = 0; i < list.length; i++) {
                if (list[i] && list[i].address === root.focusedDeviceAddress) {
                    root.focusSection = section
                    root.selectedIndex = i
                    root.clampCursor()
                    return
                }
            }
        }
        root.clampCursor()
    }

    function updateFocusedAddress() {
        var device = root.deviceAt(root.focusSection, root.selectedIndex)
        root.focusedDeviceAddress = device ? (device.address || "") : ""
    }

    function clampCursor() {
        if (root.focusSection === "header") return
        var sections = root.deviceSections
        if (!sections || sections.length === 0) {
            root.selectedIndex = 0
            root.focusSection = "header"
            return
        }
        if (sections.indexOf(root.focusSection) < 0) {
            root.focusSection = sections[0]
            root.selectedIndex = 0
            return
        }
        var count = root.sectionCount(root.focusSection)
        if (count <= 0) {
            var sectionIndex = sections.indexOf(root.focusSection)
            root.focusSection = sectionIndex > 0 ? sections[sectionIndex - 1] : sections[0]
            root.selectedIndex = Math.max(0, root.sectionCount(root.focusSection) - 1)
            return
        }
        root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex))
    }

    function siblingPanels() {
        var result = []
        var slots = root.bar && root.bar.widgetSlots ? root.bar.widgetSlots : []
        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i]
            var widget = slot && slot.pluginId === "aurelia.bluetooth" ? slot.widgetItem : null
            var panel = widget && widget.bluetoothPopup ? widget.bluetoothPopup : null
            if (panel && panel !== root) result.push(panel)
        }
        return result
    }

    function openSibling() {
        var panels = root.siblingPanels()
        for (var i = 0; i < panels.length; i++) {
            if (panels[i] && panels[i].shown === true) return panels[i]
        }
        return null
    }

    function releaseDiscoveryOnDestruction() {
        if (!root.owesDiscoveryStop) return
        var siblings = root.siblingPanels()
        if (siblings.length > 0) {
            siblings[0].owesDiscoveryStop = true
            return
        }
        if (root.adapter && root.adapter.discovering) root.adapter.discovering = false
    }

    function open(payloadJson) {
        if (!root.adapter) return "not-ready"
        root.shown = true
        root.cursorActive = false
        if (root.connectedDevices.length > 0) {
            root.focusSection = "connected"
            root.selectedIndex = 0
        } else if (root.knownDevices.length > 0) {
            root.focusSection = "known"
            root.selectedIndex = 0
        } else if (root.discoveredDevices.length > 0) {
            root.focusSection = "discovered"
            root.selectedIndex = 0
        } else {
            root.focusSection = "header"
            root.selectedIndex = 0
        }
        root.actionFocused = false
        return "ok"
    }

    function close() {
        root.shown = false
        root.actionFocused = false
        return "ok"
    }

    function toggle(payloadJson) {
        return root.shown ? root.close() : root.open(payloadJson || "{}")
    }

    function isVisible() { return root.shown === true }

    function toggleBluetooth() {
        if (!root.adapter) return
        Quickshell.execDetached([
            root.powerBin,
            root.adapter.enabled ? "off" : "on"
        ])
    }

    onShownChanged: {
        if (root.shown) {
            if (root.adapter && root.adapter.discovering) root.owesDiscoveryStop = true
            if (root.connectedDevices.length > 0) {
                root.focusSection = "connected"
                root.selectedIndex = 0
            } else if (root.knownDevices.length > 0) {
                root.focusSection = "known"
                root.selectedIndex = 0
            } else if (root.discoveredDevices.length > 0) {
                root.focusSection = "discovered"
                root.selectedIndex = 0
            } else {
                root.focusSection = "header"
            }
            root.actionFocused = false
            root.cursorActive = false
        }
    }

    onSelectedIndexChanged: root.updateFocusedAddress()
    onFocusSectionChanged: root.updateFocusedAddress()
    onConnectedDevicesChanged: {
        root.reselectFocusedDevice()
        root.syncPendingActions()
    }
    onKnownDevicesChanged: {
        root.reselectFocusedDevice()
        root.syncPendingActions()
    }
    onDiscoveredDevicesChanged: {
        root.reselectFocusedDevice()
        root.syncPendingActions()
    }
    onDeviceSectionsChanged: root.clampCursor()

    // AureliaKeyboardPanel's default property is a visual child list. Keep
    // timers and signal connections under one zero-size visual Item so URL
    // loading never inserts non-visual QObjects into that list.
    Item {
        id: runtimeControllers
        width: 0
        height: 0
        visible: false

        Timer {
            id: discoveryRetry
            interval: 1000
            repeat: true
            triggeredOnStart: true
            running: root.shown && root.adapter !== null && root.adapter.enabled &&
                !root.adapter.discovering
            onTriggered: {
                root.owesDiscoveryStop = true
                root.adapter.discovering = true
            }
        }

        Timer {
            id: discoveryStop
            interval: 1000
            repeat: true
            property int attempts: 0
            running: !root.shown && root.owesDiscoveryStop && root.adapter !== null &&
                root.adapter.discovering === true
            onRunningChanged: if (running) attempts = 0
            onTriggered: {
                var sibling = root.openSibling()
                if (sibling) {
                    sibling.owesDiscoveryStop = true
                    root.owesDiscoveryStop = false
                    return
                }
                attempts++
                if (attempts > 3) {
                    root.owesDiscoveryStop = false
                    return
                }
                root.adapter.discovering = false
            }
        }

        Connections {
            id: discoveryConnection
            target: root.adapter
            function onDiscoveringChanged() {
                if (root.adapter && !root.adapter.discovering) root.owesDiscoveryStop = false
            }
        }

        Timer {
            id: pendingTimeout
            interval: 20000
            repeat: false
            onTriggered: root.pendingActions = ({})
        }

        Timer {
            id: audioSwitchTimer
            interval: 500
            repeat: false
            onTriggered: root.switchPendingAudioOutput()
        }

        Timer {
            id: phraseTimer
            interval: 2800
            repeat: true
            running: root.shown && root.rotatingPhrases
            onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
        }

        Connections {
            id: adapterConnection
            target: root.adapter
            function onEnabledChanged() {
                root.clampCursor()
            }
        }
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: root.shown

        Keys.onPressed: function(event) { root.handleKey(event) }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            spacing: Theme.spacingSm

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 62

                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.spacingSm

                    AureliaIcon {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        name: root.iconName
                        iconSize: 34
                        tint: root.adapter && root.adapter.enabled ? Theme.accent : Theme.textMuted
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: "Bluetooth"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.weight: Theme.fontWeightBold
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.heroStatusText.toUpperCase()
                            color: Theme.textSecondary
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 0.8
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: powerSwitch
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 24
                        radius: height / 2
                        color: root.adapter && root.adapter.enabled ? Theme.accent : Theme.surface
                        border.color: root.headerHasCursor ? Theme.borderActive : Theme.border
                        border.width: root.headerHasCursor ? Theme.borderWidthFocus : Theme.borderWidthDefault

                        Rectangle {
                            width: 18
                            height: 18
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.adapter && root.adapter.enabled ? parent.width - width - 3 : 3
                            color: root.adapter && root.adapter.enabled ? Theme.bgBase : Theme.textMuted
                        }

                        HoverHandler {
                            onHoveredChanged: if (hovered) root.setHeaderCursor()
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                mouse.accepted = true
                                root.setHeaderCursor()
                                root.toggleBluetooth()
                            }
                        }

                        AureliaToolTip {
                            triggerItem: powerSwitch
                            bar: root.bar
                            hovered: powerSwitchHover.hovered
                            text: root.toggleHint
                        }

                        HoverHandler { id: powerSwitchHover }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.border
                opacity: 0.65
            }

            ColumnLayout {
                id: connectedList
                Layout.fillWidth: true
                visible: root.connectedRows.length > 0
                spacing: Theme.spacingXs

                Text {
                    Layout.fillWidth: true
                    text: "CONNECTED"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightBold
                    font.letterSpacing: 1
                }

                Repeater {
                    model: root.connectedRows

                    BluetoothDeviceRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        dev: modelData
                        rowIndex: index
                        sectionName: "connected"
                        isDiscovered: false
                        pendingAction: root.pendingAction(modelData.address)
                        rowSelected: root.cursorActive && root.focusSection === "connected" &&
                            root.selectedIndex === index
                        actionFocused: root.actionFocused
                        hoverFill: Theme.selectionHover
                        selectedFill: Theme.selectionActive
                        onActivated: root.activateRow(modelData, "connected")
                        onSecondaryActivated: root.secondaryRow(modelData, "connected")
                        onForgetRequested: root.forgetDevice(root.deviceFor(modelData))
                        onCursorEntered: root.pointerEntered("connected", index)
                        onForgetHovered: function(hovered) {
                            if (hovered) {
                                root.cursorActive = true
                                root.focusSection = "connected"
                                root.selectedIndex = index
                                root.actionFocused = true
                            } else if (root.focusSection === "connected" && root.selectedIndex === index) {
                                root.actionFocused = false
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.connectedRows.length > 0 && root.scrollRows.length > 0
                height: visible ? 1 : 0
                color: Theme.border
                opacity: 0.65
            }

            ListView {
                id: deviceList
                Layout.fillWidth: true
                Layout.fillHeight: root.scrollRows.length > 0
                Layout.preferredHeight: root.scrollRows.length > 0 ? 1 : 0
                Layout.minimumHeight: 0
                clip: true
                spacing: Theme.spacingSm
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                model: root.scrollRows
                currentIndex: root.scrollRowIndex

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(keepCurrentVisible)
                function keepCurrentVisible() {
                    if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                }

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: deviceList.width
                    height: delegateColumn.implicitHeight

                    Column {
                        id: delegateColumn
                        width: parent.width
                        spacing: Theme.spacingXs

                        Rectangle {
                            width: parent.width
                            height: 1
                            visible: index > 0 && root.scrollSectionTitle(index) !== ""
                            color: Theme.border
                            opacity: 0.65
                        }

                        Text {
                            width: parent.width
                            visible: root.scrollSectionTitle(index) !== ""
                            text: root.scrollSectionTitle(index)
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 1
                        }

                        BluetoothDeviceRow {
                            width: parent.width
                            dev: modelData.dev
                            rowIndex: modelData.indexInSection
                            sectionName: modelData.section
                            isDiscovered: modelData.section === "discovered"
                            pendingAction: root.pendingAction(modelData.dev.address)
                            rowSelected: root.cursorActive && root.focusSection === modelData.section &&
                                root.selectedIndex === modelData.indexInSection
                            actionFocused: root.actionFocused
                            hoverFill: Theme.selectionHover
                            selectedFill: Theme.selectionActive
                            onActivated: root.activateRow(modelData.dev, modelData.section)
                            onSecondaryActivated: root.secondaryRow(modelData.dev, modelData.section)
                            onForgetRequested: root.forgetDevice(root.deviceFor(modelData.dev))
                            onCursorEntered: root.pointerEntered(modelData.section, modelData.indexInSection)
                            onForgetHovered: function(hovered) {
                                if (hovered) {
                                    root.cursorActive = true
                                    root.focusSection = modelData.section
                                    root.selectedIndex = modelData.indexInSection
                                    root.actionFocused = true
                                } else if (root.focusSection === modelData.section &&
                                    root.selectedIndex === modelData.indexInSection) {
                                    root.actionFocused = false
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.fillHeight: root.connectedRows.length === 0 && root.scrollRows.length === 0
                visible: root.connectedRows.length === 0 && root.scrollRows.length === 0
                text: !root.adapter ? "No Bluetooth adapter" :
                    (!root.adapter.enabled ? "Turn Bluetooth on to scan" : "Scanning for devices…")
                color: Theme.textSecondary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
