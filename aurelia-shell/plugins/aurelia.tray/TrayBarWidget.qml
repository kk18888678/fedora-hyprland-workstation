import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"
import "../../ui"

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

    implicitWidth: trayRow.implicitWidth
    implicitHeight: bar ? bar.barSize : 32
    visible: SystemTray.items && SystemTray.items.values.length > 0

    function isSymbolicIcon(icon) {
        var name = String(icon || "").split("?")[0]
        return name.slice(-9) === "-symbolic"
    }

    function isChatGptItem(item) {
        var identity = [
            item && item.id ? item.id : "",
            item && item.title ? item.title : "",
            item && item.tooltipTitle ? item.tooltipTitle : "",
            item && item.tooltipDescription ? item.tooltipDescription : ""
        ].join("|").toLowerCase()
        return identity.indexOf("chatgpt") >= 0 || identity.indexOf("openai") >= 0
    }

    function trayIconSize(item) {
        var normal = root.bar && root.bar.barTrayIcon ? root.bar.barTrayIcon : Theme.bar.trayIcon
        var optical = root.bar && root.bar.barIconCanvas ? root.bar.barIconCanvas : Theme.bar.iconCanvas
        return root.isChatGptItem(item) ? Math.max(normal, optical) : normal
    }

    function configureTrayMenu(target) {
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("barSize" in target) target.barSize = root.bar ? root.bar.barSize : 26
    }

    function openTrayMenu(item, anchorItem) {
        if (trayMenuPanel && typeof trayMenuPanel.openForItem === "function") {
            activeTrayItem = item
            trayMenuPanel.openForItem(item, trayMenuOpener, anchorItem)
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

    RowLayout {
        id: trayRow
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayDelegate
                required property var modelData
                Layout.preferredWidth: root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : 27
                Layout.preferredHeight: root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : Theme.bar.iconSlot

                AureliaIcon {
                    anchors.centerIn: parent
                    width: root.trayIconSize(modelData)
                    height: root.trayIconSize(modelData)
                    iconSize: width
                    name: ""
                    sourcePath: modelData && modelData.icon ? String(modelData.icon) : ""
                    sourcePixelRatio: Screen.devicePixelRatio
                    smooth: false
                    preserveColors: !root.isSymbolicIcon(modelData && modelData.icon ? String(modelData.icon) : "")
                    tint: Theme.textSecondary
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
                            else modelData.activate()
                        } else if (mouse.button === Qt.MiddleButton) {
                            modelData.secondaryActivate()
                        }
                    }
                }

            }
        }

    }
}
