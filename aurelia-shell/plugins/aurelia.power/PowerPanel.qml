import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../../ui"
import "../../theme"
import "Model.js" as Model

// Omarchy-aligned Power panel. UPower owns battery truth; this panel owns
// bounded snapshots, profile intent, and the Aurelia presentation.
AureliaKeyboardPanel {
    id: root

    property var shell: null
    property string moduleName: "aurelia.power"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null

    // These overrides are unused in production. They provide deterministic
    // isolated-QML inputs without replacing the live UPower owner.
    property var displayDeviceOverride
    property var onBatteryOverride
    property var statesOverride
    property QtObject runtime: PowerRuntime { owner: root }

    property var batteryInfo: ({})
    property var systemInfo: ({})
    property var profiles: []
    property string activeProfile: ""
    property int profileIndex: 0
    property bool cursorActive: false
    property bool actionRunning: false
    property string actionError: ""
    property string profileError: ""

    function readDisplayDevice() {
        try { return UPower.displayDevice } catch (error) {
            console.warn("[POWER] UPower unavailable reason=display-device")
            return null
        }
    }

    function readOnBattery() {
        try { return !!UPower.onBattery } catch (error) {
            console.warn("[POWER] UPower unavailable reason=on-battery")
            return false
        }
    }

    function readPowerStates() {
        return {
            Charging: UPowerDeviceState.Charging,
            Discharging: UPowerDeviceState.Discharging,
            FullyCharged: UPowerDeviceState.FullyCharged,
            PendingCharge: UPowerDeviceState.PendingCharge
        }
    }

    readonly property var displayDevice: root.displayDeviceOverride !== undefined
        ? root.displayDeviceOverride : root.readDisplayDevice()
    readonly property bool onBattery: root.onBatteryOverride !== undefined
        ? root.onBatteryOverride === true : root.readOnBattery()
    readonly property var powerStates: root.statesOverride !== undefined
        ? root.statesOverride : root.readPowerStates()
    readonly property bool batteryPresent: !!(root.displayDevice &&
        root.displayDevice.isPresent === true)
    readonly property bool discharging: root.batteryPresent && root.onBattery
    readonly property real batteryFraction: Model.batteryFraction(root.displayDevice)
    readonly property bool chargeThresholdActive: Model.chargeThresholdActive(
        root.displayDevice, root.onBattery, root.powerStates)
    readonly property bool fullyCharged: root.batteryPresent &&
        root.displayDevice.state === root.powerStates.FullyCharged &&
        !root.chargeThresholdActive
    readonly property bool batteryFull: root.fullyCharged ||
        (!root.discharging && root.batteryFraction >= 1)
    readonly property bool batteryFlowIdle: root.batteryFull || root.chargeThresholdActive
    readonly property bool charging: root.batteryPresent && !root.onBattery &&
        !root.batteryFlowIdle
    readonly property bool showPercentage: !!(root.settings &&
        root.settings.showPercentage === true)
    readonly property string percentageText: Model.percentageText(root.displayDevice)
    readonly property string modeText: Model.modeLabel(
        root.displayDevice, root.onBattery, root.powerStates)
    readonly property string statusText: root.fullyCharged
        ? "Fully charged"
        : (root.chargeThresholdActive ? "Threshold" : root.modeText)
    readonly property color batteryFillColor: root.discharging ? Theme.warning : Theme.accent
    readonly property var chargingPhrases: [
        "Pumping power", "Injecting electrons", "Pouring juice", "Amassing watts",
        "Hoarding joules", "Sucking volts", "Topping reserves", "Soaking amps"
    ]
    readonly property var onBatteryPhrases: [
        "Slurping power", "Spending joules", "Draining watts", "Burning electrons",
        "Sipping juice", "Spending coulombs", "Bleeding amps", "Guzzling volts"
    ]
    property int phraseIndex: 0
    readonly property var activePhrases: root.fullyCharged ? []
        : (root.charging ? root.chargingPhrases
            : (root.discharging ? root.onBatteryPhrases : []))
    readonly property string heroStatusText: root.activePhrases.length > 0
        ? root.activePhrases[root.phraseIndex % root.activePhrases.length]
        : root.statusText
    ownerId: "aurelia.power"
    popupWidth: 380
    popupHeight: 560
    fitHeightToContent: true
    minPopupHeight: 220
    maxPopupHeight: 560
    contentSizingItem: contentColumn
    focusTarget: keyScope
    shown: false

    function batteryIcon() {
        return Model.batteryIcon(root.displayDevice, root.discharging, root.powerStates)
    }

    function profileIcon(name) { return Model.profileIcon(name) }

    function displayBatterySnapshot() {
        return Model.batterySnapshot(root.displayDevice, root.onBattery, root.powerStates)
    }

    function open(payloadJson) {
        if (!root.batteryPresent) {
            root.shown = false
            return "unavailable"
        }
        root.actionError = ""
        root.profileError = ""
        root.cursorActive = false
        root.shown = true
        root.refresh()
        return "ok"
    }

    function close() {
        root.cursorActive = false
        root.shown = false
        return "ok"
    }

    function closeForPopoutSwitch() { return root.close() }

    function toggle(payloadJson) {
        return root.shown ? root.close() : root.open(payloadJson || "{}")
    }

    function refresh() {
        if (!root.batteryPresent) return
        var snapshot = root.displayBatterySnapshot()
        if (Object.keys(snapshot).length > 0) root.batteryInfo = snapshot
        root.runtime.refresh()
    }

    function updateProfiles(raw) {
        var parsed = Model.parseProfiles(raw, root.profileIndex)
        if (parsed.profiles.length === 0) {
            root.profileError = "No power profiles are currently available."
            return
        }
        root.profiles = parsed.profiles
        root.activeProfile = parsed.activeProfile
        root.profileIndex = parsed.profileIndex
        root.profileError = ""
        if (root.shown && !root.cursorActive) {
            var activeIndex = root.profiles.indexOf(root.activeProfile)
            if (activeIndex >= 0) root.profileIndex = activeIndex
        }
    }

    function updateSystemStats(raw) {
        var parsed = Model.parseSystemStats(raw)
        if (Object.keys(parsed).length === 0) return
        var next = Object.assign({}, root.systemInfo, parsed)
        root.systemInfo = next
    }

    function runCommand(argv, kind) {
        return root.runtime.runCommand(argv, kind)
    }

    function setProfile(profile) {
        var requested = String(profile || "")
        if (!requested || root.profiles.indexOf(requested) < 0) {
            root.profileError = "Power profile is not available: " + requested
            return "unavailable"
        }
        root.profileIndex = root.profiles.indexOf(requested)
        var result = root.runCommand(["/usr/bin/powerprofilesctl", "set", requested], "profile")
        if (result === "ok" || result === "pending") root.profileError = ""
        return result
    }

    function selectProfileByDelta(delta) {
        root.profileIndex = Model.selectProfileIndex(root.profileIndex, delta, root.profiles)
        root.cursorActive = true
    }

    function activateSelectedProfile() {
        if (root.profileIndex < 0 || root.profileIndex >= root.profiles.length) return "unavailable"
        return root.setProfile(root.profiles[root.profileIndex])
    }

    function togglePercentage() {
        var next = Object.assign({}, root.settings || {}, {
            showPercentage: !root.showPercentage
        })
        root.settings = next
        if (!root.shell || typeof root.shell.updateEntryInline !== "function") return "not-ready"
        var result = String(root.shell.updateEntryInline(
            root.moduleName, JSON.stringify(next), "{}") || "")
        if (result !== "ok") root.actionError = result || "Could not save Power setting."
        return result
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            root.selectProfileByDelta(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            root.selectProfileByDelta(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activateSelectedProfile()
            event.accepted = true
        }
    }

    onShownChanged: {
        if (root.shown) {
            if (!root.batteryPresent) {
                root.shown = false
                return
            }
            root.cursorActive = false
            root.refresh()
            Qt.callLater(function() {
                if (root.shown && keyScope && typeof keyScope.forceActiveFocus === "function")
                    keyScope.forceActiveFocus()
            })
        }
    }
    onBatteryPresentChanged: if (!root.batteryPresent && root.shown) root.close()

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: root.shown
        Keys.onPressed: function(event) { root.handleKey(event) }

        Column {
            id: contentColumn
            anchors.fill: parent
            spacing: Theme.spacingMd

            Item {
                id: heroSection
                width: parent.width
                height: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)
                    + Theme.spacingSm

                AureliaIcon {
                    id: heroIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    height: 42
                    iconSize: 38
                    glyph: root.batteryIcon()
                    tint: Theme.text
                }

                Column {
                    id: heroLabels
                    anchors.left: heroIcon.right
                    anchors.leftMargin: Theme.spacingSm
                    anchors.right: heroPercent.left
                    anchors.rightMargin: Theme.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: "Battery"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Theme.fontWeightBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.heroStatusText.toUpperCase()
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        font.weight: Theme.fontWeightBold
                        font.letterSpacing: 1
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: heroPercent
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.percentageText
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXl
                    font.weight: Theme.fontWeightBold
                }
            }

            Item {
                id: progressSection
                width: parent.width
                height: 8

                Rectangle {
                    id: progressTrack
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.controls.normalFill
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(Theme.borderWidthDefault, parent.width * root.batteryFraction)
                    height: parent.height
                    radius: height / 2
                    color: root.batteryFillColor
                }
            }

            GridLayout {
                id: statsSection
                width: parent.width
                columns: 2
                columnSpacing: Theme.spacingLg
                rowSpacing: Theme.spacingXs

                InfoPair { label: "Battery size"; value: root.batteryInfo.size || "—" }
                InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
                InfoPair {
                    label: root.chargeThresholdActive ? "Charge limit" :
                        (root.discharging ? "Time left" : "Time to full")
                    value: root.chargeThresholdActive
                        ? (root.batteryInfo.threshold || "—")
                        : (root.batteryInfo.time || "—")
                }
                InfoPair { label: "Power draw"; value: root.batteryInfo.rate || "—" }
                InfoPair { label: "CPU load"; value: root.systemInfo.load || "—" }
                InfoPair { label: "Memory"; value: root.systemInfo.memory || "—" }
            }

            Column {
                id: profilesSection
                width: parent.width
                spacing: Theme.spacingXs
                visible: root.profiles.length > 0 || root.profileError !== ""

                Text {
                    width: parent.width
                    text: "POWER PROFILE"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: Theme.fontWeightBold
                    font.letterSpacing: 1
                }

                Row {
                    id: profileRow
                    width: parent.width
                    spacing: Theme.spacingXs

                    Repeater {
                        model: root.profiles
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: root.profiles.length > 0
                                ? (profileRow.width - profileRow.spacing * (root.profiles.length - 1)) /
                                    root.profiles.length : 0
                            height: 48
                            radius: Theme.radiusSm
                            color: root.profileIndex === index && root.cursorActive
                                ? Theme.selectionActive
                                : (root.activeProfile === modelData ? Theme.selection : Theme.surface)
                            border.color: root.activeProfile === modelData
                                ? Theme.borderActive : Theme.border
                            border.width: Theme.borderWidthDefault

                            Column {
                                anchors.centerIn: parent
                                spacing: 1
                                AureliaIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 18
                                    height: 18
                                    iconSize: 16
                                    glyph: root.profileIcon(String(modelData))
                                    tint: root.activeProfile === modelData ? Theme.accent : Theme.textSecondary
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: String(modelData).replace(/^./, function(c) { return c.toUpperCase() })
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    root.cursorActive = true
                                    root.profileIndex = index
                                }
                                onClicked: function(mouse) {
                                    mouse.accepted = true
                                    root.cursorActive = true
                                    root.profileIndex = index
                                    root.setProfile(String(modelData))
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.profileError !== ""
                    text: root.profileError
                    color: Theme.warning
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: root.actionError !== ""
                    text: root.actionError
                    color: Theme.warning
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    elide: Text.ElideRight
                }
            }

        }
    }

    component InfoPair: RowLayout {
        required property string label
        required property string value
        Layout.fillWidth: true
        spacing: Theme.spacingXs

        Text {
            Layout.fillWidth: true
            text: parent.label
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            elide: Text.ElideRight
        }
        Text {
            text: parent.value
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            horizontalAlignment: Text.AlignRight
        }
    }
}
