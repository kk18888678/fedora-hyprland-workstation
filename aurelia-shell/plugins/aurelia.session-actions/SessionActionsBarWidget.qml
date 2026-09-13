import QtQuick
import "../../theme"
import "../../ui"

// Battery-independent session-action affordance. Battery presentation remains
// owned by aurelia.power; this widget restores the former Aurelia action menu
// without coupling it to UPower availability.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.session-actions"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var barAnchorItem: null
    // Test-only injection. Production leaves this undefined and loads the real
    // SessionActionsPanel entry point through the normal Loader boundary.
    property var panelOverride

    readonly property var sessionPanel: root.panelOverride !== undefined
        ? root.panelOverride : panelLoader.item
    readonly property bool actionReady: !!root.sessionPanel

    implicitWidth: root.bar ? root.bar.barSize : 26
    implicitHeight: root.bar ? root.bar.barSize : 26
    visible: true

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

    function open(payloadJson) {
        if (!root.sessionPanel || typeof root.sessionPanel.open !== "function") return "not-ready"
        root.configurePanel(root.sessionPanel)
        var result = String(root.sessionPanel.open(payloadJson || "{}") || "ok")
        console.info("[SESSION-ACTIONS] panel_open result=" + result)
        return result
    }

    function close() {
        if (!root.sessionPanel || typeof root.sessionPanel.close !== "function") return "not-ready"
        return String(root.sessionPanel.close() || "ok")
    }

    function toggle(payloadJson) {
        if (!root.sessionPanel) return "not-ready"
        return root.sessionPanel.shown === true ? root.close() : root.open(payloadJson || "{}")
    }

    function handleClick(button) {
        if (button !== Qt.LeftButton) return "ignored"
        return root.toggle("{}")
    }

    function isVisible() {
        return !!root.sessionPanel && root.sessionPanel.shown === true
    }

    Loader {
        id: panelLoader
        active: root.panelOverride === undefined
        source: Qt.resolvedUrl("SessionActionsPanel.qml")
        onLoaded: {
            root.configurePanel(item)
            console.info("[SESSION-ACTIONS] panel_ready")
        }
        onStatusChanged: {
            if (status === Loader.Error) console.error("[SESSION-ACTIONS] panel_load_failed")
        }
    }

    onBarChanged: root.configurePanel(root.sessionPanel)
    onShellChanged: root.configurePanel(root.sessionPanel)
    onSettingsChanged: root.configurePanel(root.sessionPanel)
    onBarAnchorItemChanged: root.configurePanel(root.sessionPanel)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: root.isVisible() || sessionHover.hovered ? Theme.selection : "transparent"

        HoverHandler { id: sessionHover }

        AureliaIcon {
            anchors.centerIn: parent
            width: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            height: root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : 16
            iconSize: root.bar && root.bar.barIconFont ? root.bar.barIconFont : 13
            name: "system-shutdown"
            fallbackName: "system-power-off"
            tint: root.isVisible() || sessionHover.hovered ? Theme.text : Theme.textSecondary
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
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
        hovered: sessionHover.hovered
        text: "Session actions"
    }
}
