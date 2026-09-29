import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../theme"
import "../../ui"
import "../../services"
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
    // Isolated-fixture seam: production reads the live compositor model, while
    // a disposable fixture can pin a deterministic toplevel list without
    // connecting to or mutating Hyprland. Unused in production.
    property var toplevelsOverride
    readonly property var toplevelValues: root.toplevelsOverride !== undefined
        ? root.toplevelsOverride
        : (Hyprland.toplevels ? Hyprland.toplevels.values : null)
    // The desktop-entry scan is asynchronous; referencing its count keeps the
    // per-window lookup reactive so an icon appears once the scan completes.
    readonly property int desktopEntryCount: DesktopEntries.applications.values.length
    implicitWidth: root.vertical ? (bar ? bar.barSize : 26) : taskRow.implicitWidth
    implicitHeight: root.vertical ? taskRow.implicitHeight : (bar ? bar.barSize : 26)
    visible: root.toplevelValues && root.toplevelValues.length > 0

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

    // The shared AppIconResolver owns the ordered icon chain and the
    // symbolic-versus-logo rule. The caller supplies only the identity it
    // actually holds: the desktop entry's Icon= as the app-icon hint and the
    // compositor app id as the in-flight window origin. The old ad-hoc
    // chatgpt/chrom/kate/foot class heuristics now live in the owner.
    function iconResolutionFor(windowTarget, appEntry) {
        var handle = windowTarget && windowTarget.handle
        var appId = handle && handle.appId ? String(handle.appId) : ""
        return AppIconResolver.resolve({
            appIcon: appEntry && appEntry.icon ? String(appEntry.icon) : "",
            desktopEntry: appId,
            appName: appEntry && appEntry.name ? String(appEntry.name) : appId,
            origin: { appId: appId, className: appId }
        })
    }

    // Isolated-fixture read-outs. Production renders the same per-delegate
    // resolution; these let the disposable fixture assert the resolved outcome
    // rather than restating it.
    function iconResolutionAt(index) {
        var delegate = taskRepeater.itemAt(index)
        return delegate ? delegate.iconResolution : null
    }
    function iconSourceAt(index) {
        var delegate = taskRepeater.itemAt(index)
        return delegate ? delegate.iconSource : ""
    }
    function iconPreservesColorsAt(index) {
        var delegate = taskRepeater.itemAt(index)
        return delegate ? delegate.iconPreservesColors : false
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
        columns: root.vertical ? 1 : Math.max(1, root.toplevelValues ? root.toplevelValues.length : 1)
        columnSpacing: root.vertical ? 0 : Theme.spacingXs
        rowSpacing: 0

        Repeater {
            id: taskRepeater
            model: root.toplevelValues

            delegate: Item {
                id: taskDelegate
                required property var modelData
                Layout.preferredWidth: root.vertical ? (root.bar ? root.bar.barSize : 26) : 24
                Layout.preferredHeight: root.vertical
                    ? (root.bar && root.bar.barIconSlot ? root.bar.barIconSlot : 27)
                    : (root.bar ? root.bar.barSize - 6 : 20)

                readonly property var appEntry: {
                    var scan = root.desktopEntryCount
                    var handle = modelData.handle
                    var appId = handle && handle.appId ? handle.appId : ""
                    return appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
                }
                // Resolution is recomputed from change handlers rather than a
                // function-binding so the shared FileView probe cannot create
                // a binding dependency on its own caches; this is the same
                // pattern the active-window widget uses. The owner remains the
                // only place the symbolic rule is decided.
                property var iconResolution: ({ source: "", name: "", symbolic: false, kind: "default", origin: "default" })
                function refreshIconResolution() {
                    taskDelegate.iconResolution = root.iconResolutionFor(modelData, taskDelegate.appEntry)
                }
                readonly property string iconSource: String(taskDelegate.iconResolution.source || "")
                readonly property bool symbolicIcon: taskDelegate.iconResolution.symbolic === true
                Component.onCompleted: taskDelegate.refreshIconResolution()
                onAppEntryChanged: taskDelegate.refreshIconResolution()
                Connections {
                    target: AppIconResolver
                    function onMetadataIndexRevisionChanged() { taskDelegate.refreshIconResolution() }
                }

                AureliaIcon {
                    id: taskIcon
                    anchors.centerIn: parent
                    width: root.iconCanvas
                    height: root.iconCanvas
                    iconSize: root.iconCanvas
                    name: ""
                    sourcePath: taskDelegate.iconSource
                    // The owner decides mask versus logo: only a symbolic mask
                    // may be tinted, every real application logo keeps its
                    // colours.
                    preserveColors: !taskDelegate.symbolicIcon
                    tint: root.barForeground
                    // The single documented inactive dim: running but unfocused.
                    opacity: modelData.activated ? 1.0 : 0.65
                }
                readonly property bool iconPreservesColors: taskIcon.preserveColors

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
