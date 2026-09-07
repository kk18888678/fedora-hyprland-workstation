import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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

    implicitWidth: trayRow.implicitWidth
    implicitHeight: bar ? bar.barSize : 32
    visible: (SystemTray.items && SystemTray.items.values.length > 0) || (Hyprland.toplevels && Hyprland.toplevels.values.length > 0)

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
                        if (mouse.button === Qt.RightButton && modelData.hasMenu) {
                            trayMenu.open()
                        } else if (mouse.button === Qt.LeftButton) {
                            if (modelData.onlyMenu && modelData.hasMenu) trayMenu.open()
                            else modelData.activate()
                        } else if (mouse.button === Qt.MiddleButton) {
                            modelData.secondaryActivate()
                        }
                    }
                }

                QsMenuAnchor {
                    id: trayMenu
                    menu: modelData.menu
                    anchor.item: trayDelegate
                }
            }
        }

        Repeater {
            model: Hyprland.toplevels

            delegate: Item {
                required property var modelData
                Layout.preferredWidth: 24
                Layout.preferredHeight: root.bar ? root.bar.barSize - 6 : 26

                readonly property var appEntry: {
                    var handle = modelData.handle
                    var appId = handle && handle.appId ? handle.appId : ""
                    return appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
                }

                Image {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: appEntry && appEntry.icon
                        ? Quickshell.iconPath(appEntry.icon, "application-x-executable")
                        : Quickshell.iconPath("application-x-executable")
                    sourceSize: Qt.size(20, 20)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    opacity: modelData.activated ? 1.0 : 0.65
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        if (modelData.handle) modelData.handle.activate()
                    }
                }
            }
        }
    }
}
