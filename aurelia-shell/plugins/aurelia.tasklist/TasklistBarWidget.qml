import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../theme"
import "../../ui"
import "../../services/WindowRouting.js" as WindowRouting

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
    readonly property color barForeground: root.bar && root.bar.barForeground !== undefined
        ? root.bar.barForeground : Theme.text
    // Uniform bar-icon contract: one 16 px ink canvas scaled by the bar, no
    // literal sizes. Icon artwork stays tinted to the bar foreground.
    readonly property int iconCanvas: root.bar && root.bar.barIconCanvas
        ? root.bar.barIconCanvas : Theme.bar.iconCanvas

    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    implicitWidth: root.vertical ? (bar ? bar.barSize : 26) : taskRow.implicitWidth
    implicitHeight: root.vertical ? taskRow.implicitHeight : (bar ? bar.barSize : 26)
    visible: Hyprland.toplevels && Hyprland.toplevels.values.length > 0

    function configureMenu(target) {
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("barSize" in target) target.barSize = root.bar ? root.bar.barSize : 26
        if ("activationController" in target) target.activationController = windowActivationLoader.item
    }

    function openWindowMenu(windowTarget, anchorItem) {
        if (menuPanel && typeof menuPanel.openForWindow === "function") menuPanel.openForWindow(windowTarget, anchorItem || root)
    }

    function openMatchingWindowMenu(identity) {
        var values = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var route = WindowRouting.workspaceRouteDataForTrayIdentity(identity)
        var match = WindowRouting.matchingWorkspaceToplevel(route, values)
        if (match && match.toplevel && match.toplevel.handle) {
            openWindowMenu(match.toplevel, root)
            return "ok"
        }
        return "not-found"
    }

    function activateWindow(windowTarget) {
        return windowActivationLoader.item && typeof windowActivationLoader.item.activate === "function"
            ? windowActivationLoader.item.activate(windowTarget) : "not-loaded"
    }

    Loader {
        id: windowActivationLoader
        active: true
        source: Qt.resolvedUrl("../../services/WindowActivation.qml")
        onLoaded: root.configureMenu(menuLoader.item)
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

    GridLayout {
        id: taskRow
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, Hyprland.toplevels ? Hyprland.toplevels.values.length : 1)
        columnSpacing: root.vertical ? 0 : Theme.spacingXs
        rowSpacing: 0

        Repeater {
            model: Hyprland.toplevels

            delegate: Item {
                id: taskDelegate
                required property var modelData
                Layout.preferredWidth: root.vertical ? (root.bar ? root.bar.barSize : 26) : 24
                Layout.preferredHeight: root.vertical
                    ? (root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : 27)
                    : (root.bar ? root.bar.barSize - 6 : 20)

                readonly property var appEntry: {
                    var handle = modelData.handle
                    var appId = handle && handle.appId ? handle.appId : ""
                    return appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
                }

                AureliaIcon {
                    anchors.centerIn: parent
                    width: root.iconCanvas
                    height: root.iconCanvas
                    iconSize: root.iconCanvas
                    name: ""
                    sourcePath: root.iconSourceFor(modelData, appEntry)
                    tint: root.barForeground
                    // The single documented inactive dim: running but unfocused.
                    opacity: modelData.activated ? 1.0 : 0.65
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.AllButtons
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        if (mouse.button === Qt.RightButton) root.openWindowMenu(modelData, taskDelegate)
                        else if (mouse.button === Qt.LeftButton && modelData.handle) root.activateWindow(modelData)
                    }
                }
            }
        }
    }
}
