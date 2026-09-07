import QtQuick
import "../../theme"

// A single manifest-backed bar widget. The bar owns placement; the widget
// owns its visual content and action. This keeps third-party widgets on the
// same boundary as panels without making the bar know their implementation.
Item {
    id: root

    property var bar: null
    property var shell: null
    property var pluginRegistry: null
    property string aureliaPath: ""
    property string pluginId: ""
    property var settings: ({})
    property bool active: true

    readonly property var pluginManifest: pluginRegistry && pluginRegistry.isKnown(pluginId)
        ? pluginRegistry.installedPlugins[pluginId]
        : null
    readonly property bool available: {
        var revision = pluginRegistry ? pluginRegistry.registryRevision : 0
        return revision >= 0 && pluginManifest !== null &&
            pluginManifest.kinds && pluginManifest.kinds.indexOf("bar-widget") !== -1 &&
            pluginRegistry.isEnabled(pluginId)
    }
    readonly property var widgetItem: widgetLoader.item
    readonly property bool popoutActive: root.bar && root.bar.activePopoutId === root.pluginId

    implicitWidth: visible && widgetItem ? Math.max(0, Number(widgetItem.implicitWidth || 0)) : 0
    implicitHeight: visible && widgetItem ? Math.max(1, Number(widgetItem.implicitHeight || (bar ? bar.barSize : 38))) : 0
    visible: active && available && widgetItem !== null

    function configure(target) {
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("shell" in target) target.shell = root.shell
        if ("aureliaPath" in target) target.aureliaPath = root.aureliaPath
        if ("moduleName" in target) target.moduleName = root.pluginId
        if ("settings" in target) target.settings = root.settings || ({})
        if ("manifest" in target) target.manifest = root.pluginManifest || ({})
        if ("pluginRegistry" in target) target.pluginRegistry = root.pluginRegistry
    }

    function invoke(method, argument) {
        if (!widgetItem || typeof widgetItem[method] !== "function") return "not-loaded"
        if (argument === undefined || argument === null || argument === "") return String(widgetItem[method]() || "")
        return String(widgetItem[method](argument) || "")
    }

    Loader {
        id: widgetLoader
        anchors.fill: parent
        active: root.active && root.available
        source: active ? root.pluginRegistry.entryPointUrl(root.pluginId, "bar-widget") : ""

        onLoaded: root.configure(item)
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[BAR] aurelia.bar.widget_load_failed id=" + root.pluginId)
            }
        }
    }

    onSettingsChanged: root.configure(widgetLoader.item)

    Rectangle {
        visible: root.popoutActive
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 2
        color: Theme.accent
        z: 20
    }

    Component.onCompleted: if (root.bar && typeof root.bar.registerWidgetSlot === "function") root.bar.registerWidgetSlot(root)
    Component.onDestruction: if (root.bar && typeof root.bar.unregisterWidgetSlot === "function") root.bar.unregisterWidgetSlot(root)
}
