import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"
import "../../ui"
import "../../services/WindowRouting.js" as WindowRouting
import "TrayIconPolicy.js" as TrayIconPolicy

// Quickshell's SystemTray singleton tracks StatusNotifier applications. This
// is deliberately a bar widget; it does not become a second tray process.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.tray"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    property var activeTrayItem: null
    readonly property var trayMenuPanel: trayMenuLoader.item
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text
    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    // Uniform bar-icon contract: every tray item renders in the same 16 px ink
    // canvas scaled by the bar, with no per-item special cases.
    readonly property int iconCanvas: root.bar && root.bar.barIconCanvas
        ? root.bar.barIconCanvas : Theme.bar.iconCanvas

    implicitWidth: root.vertical ? (bar ? bar.barSize : 32) : trayRow.implicitWidth
    implicitHeight: root.vertical ? trayRow.implicitHeight : (bar ? bar.barSize : 32)
    visible: SystemTray.items && SystemTray.items.values.length > 0

    function configureTrayMenu(target) {
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("barSize" in target) target.barSize = root.bar ? root.bar.barSize : 26
    }

    function startTrayRoute(item) {
        var route = WindowRouting.workspaceRouteDataForTrayItem(item)
        return route.enabled && windowActivationLoader.item
            ? windowActivationLoader.item.start(route) : "unavailable"
    }

    function activateTrayItem(item) {
        try {
            item.activate()
            root.startTrayRoute(item)
            return "ok"
        } catch (error) {
            console.warn("[TRAY] item_activation_failed")
            return "error"
        }
    }

    function openTrayMenu(item, anchorItem) {
        if (trayMenuPanel && typeof trayMenuPanel.openForItem === "function") {
            activeTrayItem = item
            trayMenuPanel.openForItem(item, trayMenuOpener, anchorItem,
                function(menuItem) { return root.startTrayRoute(menuItem) })
        }
    }

    function openApplicationContextMenu(item, anchorItem) {
        var identity = [
            item && item.id ? item.id : "",
            item && item.title ? item.title : "",
            item && item.tooltipTitle ? item.tooltipTitle : "",
            item && item.tooltipDescription ? item.tooltipDescription : ""
        ].join("|")
        var taskResult = root.bar && typeof root.bar.callWidget === "function"
            ? root.bar.callWidget("aurelia.tasklist", "openMatchingWindowMenu", identity)
            : "not-loaded"
        if (taskResult !== "ok" && item && item.hasMenu) root.openTrayMenu(item, anchorItem)
    }

    Loader {
        id: windowActivationLoader
        active: true
        source: Qt.resolvedUrl("../../services/WindowActivation.qml")
    }

    Loader {
        id: trayMenuLoader
        active: true
        source: Qt.resolvedUrl("TrayMenuPanel.qml")
        onLoaded: root.configureTrayMenu(item)
    }

    // Keep the root D-Bus menu opener alive with the visible tray widget. The
    // menu panel is hidden most of the time; owning this opener there makes
    // the item title appear while its children remain unloaded.
    QsMenuOpener {
        id: trayMenuOpener
        menu: root.activeTrayItem ? root.activeTrayItem.menu : null
    }

    onBarChanged: root.configureTrayMenu(trayMenuLoader.item)

    GridLayout {
        id: trayRow
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, SystemTray.items ? SystemTray.items.values.length : 1)
        columnSpacing: 0
        rowSpacing: 0

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayDelegate
                required property var modelData
                Layout.preferredWidth: root.vertical
                    ? (root.bar && root.bar.barSize ? root.bar.barSize : 32)
                    : (root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : 27)
                Layout.preferredHeight: root.vertical
                    ? (root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : Theme.bar.iconSlot)
                    : (root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : Theme.bar.iconSlot)

                AureliaIcon {
                    anchors.centerIn: parent
                    width: root.iconCanvas
                    height: root.iconCanvas
                    iconSize: root.iconCanvas
                    name: ""
                    sourcePath: modelData && modelData.icon ? String(modelData.icon) : ""
                    sourcePixelRatio: Screen.devicePixelRatio
                    smooth: false
                    // Multi-colour brand/tray art is the single documented
                    // exception to the always-tint glyph policy.
                    preserveColors: TrayIconPolicy.preserveColors(modelData && modelData.icon ? String(modelData.icon) : "")
                    tint: root.barForeground
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.AllButtons
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        if (mouse.button === Qt.RightButton) {
                            root.openApplicationContextMenu(modelData, trayDelegate)
                        } else if (mouse.button === Qt.LeftButton) {
                            if (modelData.onlyMenu && modelData.hasMenu) root.openTrayMenu(modelData, trayDelegate)
                            else root.activateTrayItem(modelData)
                        } else if (mouse.button === Qt.MiddleButton) {
                            modelData.secondaryActivate()
                            root.startTrayRoute(modelData)
                        }
                    }
                }

            }
        }

    }
}
