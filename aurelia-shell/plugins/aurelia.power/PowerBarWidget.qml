import QtQuick
import "../../theme"
import "../../ui"

// Power's bar affordance owns only the trigger and delegates battery/profile
// presentation and actions to PowerPanel through the normal host Loader.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.power"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
    // Test-only dependency injection; production uses the loaded panel.
    property var panelOverride

    readonly property var powerPanel: root.panelOverride !== undefined
        ? root.panelOverride : panelLoader.item
    readonly property bool batteryPresent: !!(root.powerPanel && root.powerPanel.batteryPresent)
    readonly property string availabilityReason: root.batteryPresent ? "" : "no_battery"
    readonly property bool showPercentage: !!(root.powerPanel && root.powerPanel.showPercentage)
    readonly property bool vertical: !!(root.bar && root.bar.vertical)
    readonly property string statusText: root.powerPanel && root.powerPanel.statusText
        ? String(root.powerPanel.statusText) : "Power unavailable"
    property bool availabilityReported: false

    implicitWidth: root.batteryPresent
        ? (root.showPercentage && !root.vertical
            ? (root.bar && root.bar.barIconSlot ? root.bar.barIconSlot * 2 : 54)
            : (root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : 27))
        : 0
    implicitHeight: root.bar ? root.bar.barSize : 26
    visible: root.batteryPresent

    function configurePanel(target) {
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("shell" in target) target.shell = root.shell
        if ("settings" in target) target.settings = root.settings || ({})
        if ("manifest" in target) target.manifest = root.manifest || ({})
        if ("pluginRegistry" in target) target.pluginRegistry = root.pluginRegistry
        if ("barAnchorItem" in target) target.barAnchorItem = root.barAnchorItem || root
        if ("anchorItem" in target) target.anchorItem = root.barAnchorItem || root
    }

    function reportAvailability() {
        if (!root.powerPanel) return
        if (root.batteryPresent) {
            root.availabilityReported = false
            return
        }
        if (root.availabilityReported) return
        root.availabilityReported = true
        console.info("[POWER] bar_hidden reason=no_battery")
    }

    function open(payloadJson) {
        if (!root.powerPanel || typeof root.powerPanel.open !== "function") return "not-ready"
        if (!root.batteryPresent) return "unavailable"
        root.configurePanel(root.powerPanel)
        return String(root.powerPanel.open(payloadJson || "{}") || "ok")
    }

    function close() {
        if (!root.powerPanel || typeof root.powerPanel.close !== "function") return "not-ready"
        return String(root.powerPanel.close() || "ok")
    }

    function toggle() {
        if (!root.powerPanel || !root.batteryPresent) return "unavailable"
        return root.powerPanel.shown === true ? root.close() : root.open("{}")
    }

    function togglePercentage() {
        if (!root.powerPanel || typeof root.powerPanel.togglePercentage !== "function") return "not-ready"
        return String(root.powerPanel.togglePercentage() || "")
    }

    function handleClick(button) {
        if (!root.batteryPresent) return "unavailable"
        if (button === Qt.RightButton) return root.togglePercentage()
        return root.toggle()
    }

    function isVisible() {
        return !!(root.powerPanel && root.powerPanel.shown === true)
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("PowerPanel.qml")
        onLoaded: root.configurePanel(item)
        onStatusChanged: {
            if (status === Loader.Error) console.error("[POWER] panel_load_failed")
            if (status === Loader.Ready) root.reportAvailability()
        }
    }

    onBarChanged: root.configurePanel(root.powerPanel)
    onShellChanged: root.configurePanel(root.powerPanel)
    onSettingsChanged: root.configurePanel(root.powerPanel)
    onBarAnchorItemChanged: root.configurePanel(root.powerPanel)
    onPowerPanelChanged: root.reportAvailability()
    onBatteryPresentChanged: root.reportAvailability()

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: powerHover.hovered || root.isVisible() ? Theme.selection : "transparent"

        HoverHandler { id: powerHover }

        AureliaIcon {
            anchors.centerIn: parent
            width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            glyph: root.powerPanel && typeof root.powerPanel.batteryIcon === "function"
                ? root.powerPanel.batteryIcon() : ""
            tint: powerHover.hovered || root.isVisible() ? Theme.text : Theme.textSecondary
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                mouse.accepted = true
                root.handleClick(mouse.button)
            }
        }
    }

    AureliaToolTip {
        triggerItem: root
        bar: root.bar
        hovered: powerHover.hovered
        text: root.statusText
    }
}
