import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../../theme"

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

    function configureTrayMenu(target) {
        if (!target) return
        if ("anchorWindow" in target) target.anchorWindow = root.bar
        if ("barSize" in target) target.barSize = root.bar ? root.bar.barSize : 26
    }

    function openTrayMenu(item) {
        if (trayMenuPanel && typeof trayMenuPanel.openForItem === "function") {
            activeTrayItem = item
            trayMenuPanel.openForItem(item, trayMenuOpener)
        }
    }

    function openApplicationContextMenu(item) {
        var identity = [
            item && item.id ? item.id : "",
            item && item.title ? item.title : "",
            item && item.tooltipTitle ? item.tooltipTitle : "",
            item && item.tooltipDescription ? item.tooltipDescription : ""
        ].join("|")
        var taskResult = root.bar && typeof root.bar.callWidget === "function"
            ? root.bar.callWidget("aurelia.tasklist", "openMatchingWindowMenu", identity)
            : "not-loaded"
        if (taskResult !== "ok" && item && item.hasMenu) root.openTrayMenu(item)
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
        spacing: Theme.spacingXs

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayDelegate
                required property var modelData
                Layout.preferredWidth: 24
                Layout.preferredHeight: root.bar ? root.bar.barSize - 6 : 26

                Image {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: modelData.icon
                    sourceSize: Qt.size(20, 20)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.AllButtons
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        if (mouse.button === Qt.RightButton) {
                            root.openApplicationContextMenu(modelData)
                        } else if (mouse.button === Qt.LeftButton) {
                            if (modelData.onlyMenu && modelData.hasMenu) root.openTrayMenu(modelData)
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
