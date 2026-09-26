import QtQuick
import "../../ui"

// AI subscription usage panel wrapper.
//
// The visible surface is the consolidated multi-account dashboard
// (AgentsDashboard.qml). The popup BECOMES the dashboard: there is a single
// surface, no new plugin, and the keyboard/placement policy is inherited
// verbatim from AureliaKeyboardPanel (popup follows the owning bar widget;
// no centre override). The dashboard is loaded through a Loader exactly like
// the bar widget loads this panel, so the sibling type resolves regardless of
// the config folder the panel is loaded from.
AureliaKeyboardPanel {
    id: panelRoot

    property var agentsWidget: null

    bar: agentsWidget ? agentsWidget.bar : null
    ownerId: "aurelia.agents"
    popupWidth: 460
    popupHeight: 320
    fitHeightToContent: true
    contentSizingItem: dashboardLoader.item
    minPopupHeight: 220
    maxPopupHeight: 640
    focusTarget: dashboardLoader.item ? dashboardLoader.item.keyTarget : null
    shown: false

    function open(payloadJson) {
        if (!agentsWidget || !agentsWidget.hasAgents) return "not-ready"
        shown = true
        return "ok"
    }

    function close() {
        shown = false
        return "ok"
    }

    function toggle(payloadJson) {
        return shown ? close() : open(payloadJson || "{}")
    }

    function isVisible() { return shown === true }

    function closeForPopoutSwitch() { close() }

    function refreshNow(force) {
        if (agentsWidget) agentsWidget.refresh(force === true)
    }

    onShownChanged: {
        if (shown && agentsWidget && agentsWidget.maybeRefresh) agentsWidget.maybeRefresh(60000)
    }

    Loader {
        id: dashboardLoader
        anchors.fill: parent
        source: Qt.resolvedUrl("AgentsDashboard.qml")
        onLoaded: {
            item.agentsWidget = Qt.binding(function() { return panelRoot.agentsWidget })
            item.staleMs = Qt.binding(function() {
                return panelRoot.agentsWidget ? panelRoot.agentsWidget.staleMs : 1800000
            })
            item.maxHeight = Qt.binding(function() {
                return panelRoot.maxPopupHeight - panelRoot.contentPadding * 2
            })
            item.dismissHook = Qt.binding(function() {
                return function() { panelRoot.close() }
            })
        }
        onStatusChanged: {
            if (status === Loader.Error) console.error("[AGENTS] panel_load_failed")
        }
    }
}
