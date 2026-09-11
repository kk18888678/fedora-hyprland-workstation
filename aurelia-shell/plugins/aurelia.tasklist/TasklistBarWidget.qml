import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../theme"
import "../../ui"

// Running windows are not StatusNotifier tray items. Keep this widget
// separate from aurelia.tray so right-click behavior has an explicit window
// contract instead of pretending a toplevel owns a D-Bus menu.
Item {
    id: root

    property var bar: null
    property var shell: null
    property string moduleName: "aurelia.tasklist"
    property var settings: ({})
    property var manifest: ({})
    property var pluginRegistry: null
    readonly property var menuPanel: menuLoader.item

    implicitWidth: taskRow.implicitWidth
    implicitHeight: bar ? bar.barSize : 26
    visible: Hyprland.toplevels && Hyprland.toplevels.values.length > 0

    function configureMenu(target) {
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("barSize" in target) target.barSize = root.bar ? root.bar.barSize : 26
    }

    function openWindowMenu(windowTarget, anchorItem) {
        if (menuPanel && typeof menuPanel.openForWindow === "function") menuPanel.openForWindow(windowTarget, anchorItem || root)
    }

    function openMatchingWindowMenu(identity) {
        var requested = String(identity || "").toLowerCase().split("|")
        var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (var i = 0; i < values.length; i++) {
            var candidate = values[i]
            var handle = candidate ? candidate.handle : null
            var appId = handle && handle.appId ? String(handle.appId).toLowerCase() : ""
            var title = candidate && candidate.title ? String(candidate.title).toLowerCase() : ""
            var matched = false
            for (var r = 0; r < requested.length; r++) {
                var needle = requested[r].trim()
                if (needle !== "" && (appId === needle || title === needle || appId.indexOf(needle) !== -1 || title.indexOf(needle) !== -1)) {
                    matched = true
                    break
                }
            }
            if (matched && handle) {
                openWindowMenu(candidate, root)
                return "ok"
            }
        }
        return "not-found"
    }

    function iconSourceFor(windowTarget, appEntry) {
        if (appEntry && appEntry.icon) return Quickshell.iconPath(appEntry.icon, "window-new")
        var handle = windowTarget && windowTarget.handle
        var appId = handle && handle.appId ? String(handle.appId).toLowerCase() : ""
        if (appId.indexOf("chatgpt") >= 0) return Quickshell.iconPath("chatgpt", "window-new")
        if (appId.indexOf("chrom") >= 0) return Quickshell.iconPath("chromium", "window-new")
        if (appId.indexOf("kate") >= 0) return Quickshell.iconPath("kate", "window-new")
        if (appId.indexOf("foot") >= 0) return Quickshell.iconPath("utilities-terminal", "window-new")
        return Quickshell.iconPath("window-new", "applications-system")
    }

    Loader {
        id: menuLoader
        active: true
        source: Qt.resolvedUrl("TasklistMenuPanel.qml")
        onLoaded: root.configureMenu(item)
    }

    onBarChanged: root.configureMenu(menuLoader.item)

    RowLayout {
        id: taskRow
        anchors.centerIn: parent
        spacing: Theme.spacingXs

        Repeater {
            model: Hyprland.toplevels

            delegate: Item {
                id: taskDelegate
                required property var modelData
                Layout.preferredWidth: 24
                Layout.preferredHeight: root.bar ? root.bar.barSize - 6 : 20

                readonly property var appEntry: {
                    var handle = modelData.handle
                    var appId = handle && handle.appId ? handle.appId : ""
                    return appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
                }

                AureliaIcon {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    iconSize: 20
                    name: ""
                    sourcePath: root.iconSourceFor(modelData, appEntry)
                    tint: modelData.activated ? Theme.text : Theme.textMuted
                    opacity: modelData.activated ? 1.0 : 0.65
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.AllButtons
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        if (mouse.button === Qt.RightButton) root.openWindowMenu(modelData, taskDelegate)
                        else if (mouse.button === Qt.LeftButton && modelData.handle) modelData.handle.activate()
                    }
                }
            }
        }
    }
}
