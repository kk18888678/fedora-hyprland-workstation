import QtQuick
import Quickshell
import "../../theme"

// A single bar module slot. Registered manifest widgets, reviewed user QML
// modules, and argv-based command modules share one placement boundary so the
// bar does not need to know each module's implementation.
Item {
    id: root

    property var bar: null
    property var shell: null
    property var pluginRegistry: null
    property string aureliaPath: ""
    property string pluginId: ""
    property var settings: ({})
    property bool active: true
    property bool registered: false
    property bool reloading: false
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHome: {
        var override = Quickshell.env("XDG_CONFIG_HOME") || ""
        return override.charAt(0) === "/" && override !== "/" ? override : root.home + "/.config"
    }
    readonly property string customModulesRoot: root.configHome + "/aurelia/bar/modules"
    readonly property string customType: root.resolveCustomType()
    readonly property bool customQml: root.customType === "qml"
    readonly property bool customCommand: root.customType === "command"

    readonly property var pluginManifest: pluginRegistry && pluginRegistry.isKnown(pluginId)
        ? pluginRegistry.installedPlugins[pluginId]
        : null
    readonly property bool available: {
        var failureRevision = pluginRegistry ? pluginRegistry.runtimeFailureRevision : 0
        if (pluginRegistry && typeof pluginRegistry.hasActiveRuntimeFailure === "function" &&
            pluginRegistry.hasActiveRuntimeFailure(pluginId, "bar-widget")) return false
        if (root.customType !== "") return true
        var revision = pluginRegistry ? pluginRegistry.registryRevision : 0
        return revision >= 0 && pluginManifest !== null &&
            pluginManifest.kinds && pluginManifest.kinds.indexOf("bar-widget") !== -1 &&
            pluginRegistry.isEnabled(pluginId)
    }
    readonly property var widgetItem: root.customQml ? qmlLoader.item
        : (root.customCommand ? commandLoader.item : widgetLoader.item)
    readonly property bool popoutActive: root.bar && root.bar.activePopoutId === root.pluginId
    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    readonly property int barSize: root.bar && root.bar.barSize ? root.bar.barSize : 26

    function fileUrl(value) {
        var parts = String(value || "").split("/")
        for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
        return "file://" + parts.join("/")
    }

    implicitWidth: visible && widgetItem
        ? (root.vertical ? root.barSize : Math.max(0, Number(widgetItem.implicitWidth || 0)))
        : 0
    implicitHeight: visible && widgetItem
        ? (root.vertical ? Math.max(1, Number(widgetItem.implicitHeight || 0)) : root.barSize)
        : 0
    visible: active && available && widgetItem !== null

    function configure(target) {
        if (!target) return
        if ("bar" in target) target.bar = root.bar
        if ("barAnchorItem" in target) target.barAnchorItem = root
        if ("shell" in target) target.shell = root.shell
        if ("aureliaPath" in target) target.aureliaPath = root.aureliaPath
        if ("moduleName" in target) target.moduleName = root.pluginId
        if ("settings" in target) target.settings = root.settings || ({})
        if ("manifest" in target) target.manifest = root.pluginManifest || ({})
        if ("pluginRegistry" in target) target.pluginRegistry = root.pluginRegistry
    }

    function failureSource() {
        try {
            if (root.customQml) return root.fileUrl(root.safeCustomSource())
            if (root.customCommand) return Qt.resolvedUrl("CustomCommandBarWidget.qml")
            if (root.pluginRegistry && typeof root.pluginRegistry.entryPointUrl === "function")
                return String(root.pluginRegistry.entryPointUrl(root.pluginId, "bar-widget") || "")
        } catch (e) {
            return ""
        }
        return ""
    }

    function reportFailure(phase, error) {
        var detail = "bar widget failure"
        try {
            if (root.pluginRegistry && typeof root.pluginRegistry.boundedFailureDetail === "function")
                detail = root.pluginRegistry.boundedFailureDetail(error)
            else if (error) detail = String(error)
        } catch (e) {
            detail = "bar widget failure detail unavailable"
        }
        try {
            if (root.pluginRegistry && typeof root.pluginRegistry.recordRuntimeFailure === "function")
                root.pluginRegistry.recordRuntimeFailure(root.pluginId, "bar-widget", phase || "runtime",
                    root.failureSource(), "bar-widget", detail)
        } catch (registryError) {
            console.warn("[PLUGIN] aurelia.plugin.failure_recording_failed id=" + root.pluginId)
        }
        console.warn("[BAR] aurelia.bar.widget_failure id=" + root.pluginId + " phase=" + String(phase || "runtime"))
    }

    function scheduleFailure(phase, error) {
        Qt.callLater(function() {
            if (!root.pluginRegistry || typeof root.pluginRegistry.hasActiveRuntimeFailure !== "function" ||
                !root.pluginRegistry.hasActiveRuntimeFailure(root.pluginId, "bar-widget"))
                root.reportFailure(phase, error)
        })
    }

    function safeConfigure(target) {
        if (!target) return true
        try {
            root.configure(target)
            return true
        } catch (error) {
            root.reportFailure("initialization", error)
            return false
        }
    }

    function handleLoaded(target) {
        if (!root.safeConfigure(target)) return
        try {
            if (target && typeof target.aureliaInitialize === "function") target.aureliaInitialize()
            if (root.bar && typeof root.bar.bumpWidgetRevision === "function") root.bar.bumpWidgetRevision()
        } catch (error) {
            root.reportFailure("initialization", error)
        }
    }

    function safeCustomSource() {
        var value = String(root.settings && root.settings.source || "").trim()
        if (!value) value = root.pluginId
        if (value.indexOf("~/") === 0) value = root.home + value.substring(1)
        else if (value.indexOf("$HOME/") === 0) value = root.home + value.substring(5)
        else if (value.charAt(0) !== "/") value = root.customModulesRoot + "/" + value

        var prefix = root.customModulesRoot.replace(/\/$/, "") + "/"
        if (value.indexOf(prefix) !== 0 || value.indexOf("..") !== -1 ||
            value.indexOf("\\") !== -1 || value.indexOf("\n") !== -1 ||
            value.indexOf("\r") !== -1 || !/\.qml$/i.test(value)) return ""
        return value
    }

    function safeArgv(value) {
        if (!Array.isArray(value) || value.length === 0) return []
        var result = []
        for (var i = 0; i < value.length; i++) {
            var part = String(value[i])
            if (!part || part.indexOf("\n") !== -1 || part.indexOf("\r") !== -1 || part.indexOf("\0") !== -1)
                return []
            if (i === 0 && part.indexOf("/") !== -1 &&
                !part.startsWith("/usr/bin/") && !part.startsWith("/usr/local/bin/") &&
                !part.startsWith("/bin/") && !part.startsWith(root.home + "/.local/bin/")) return []
            if (part.indexOf("..") !== -1) return []
            result.push(part)
        }
        return result
    }

    function commandArgv() {
        var configured = root.settings ? root.settings.command : null
        return root.safeArgv(configured)
    }

    function resolveCustomType() {
        var configured = root.settings || ({})
        var type = String(configured.type || "").toLowerCase()
        if ((type === "qml" || (!type && configured.source !== undefined)) && root.safeCustomSource() !== "") return "qml"
        if ((type === "command" || (!type && configured.command !== undefined)) && root.commandArgv().length > 0) return "command"
        return ""
    }

    function invoke(method, argument) {
        if (!root.available) return "error"
        if (!widgetItem || typeof widgetItem[method] !== "function") return "not-loaded"
        try {
            if (argument === undefined || argument === null || argument === "") return String(widgetItem[method]() || "")
            return String(widgetItem[method](argument) || "")
        } catch (error) {
            root.reportFailure("callback", error)
            return "error"
        }
    }

    function reload() {
        if (root.reloading) return
        try {
            if (root.pluginRegistry && typeof root.pluginRegistry.clearRuntimeFailure === "function")
                root.pluginRegistry.clearRuntimeFailure(root.pluginId, "bar-widget")
        } catch (e) {
            console.warn("[PLUGIN] aurelia.plugin.failure_clear_failed id=" + root.pluginId)
        }
        root.reloading = true
        Qt.callLater(function() { root.reloading = false })
    }

    function registerWithBar() {
        if (registered || !root.bar || typeof root.bar.registerWidgetSlot !== "function") return
        root.bar.registerWidgetSlot(root)
        registered = true
    }

    function unregisterFromBar() {
        if (!registered || !root.bar || typeof root.bar.unregisterWidgetSlot !== "function") return
        root.bar.unregisterWidgetSlot(root)
        registered = false
    }

    Loader {
        id: widgetLoader
        anchors.fill: parent
        active: root.active && root.available && !root.reloading
        source: active ? root.pluginRegistry.entryPointUrl(root.pluginId, "bar-widget") : ""

        onLoaded: root.handleLoaded(item)
        onStatusChanged: {
            if (status === Loader.Error && !root.available) return
            if (status === Loader.Error) root.scheduleFailure("load", "registered widget Loader.Error")
        }
    }

    Loader {
        id: qmlLoader
        anchors.fill: parent
        active: root.customQml && !root.reloading
        source: root.customQml ? root.fileUrl(root.safeCustomSource()) : ""
        onLoaded: root.handleLoaded(item)
        onStatusChanged: {
            if (status === Loader.Error && !root.available) return
            if (status === Loader.Error) root.scheduleFailure("load", "custom QML Loader.Error")
        }
    }

    Loader {
        id: commandLoader
        anchors.fill: parent
        active: root.customCommand && !root.reloading
        source: active ? Qt.resolvedUrl("CustomCommandBarWidget.qml") : ""
        onLoaded: root.handleLoaded(item)
        onStatusChanged: {
            if (status === Loader.Error && !root.available) return
            if (status === Loader.Error) root.scheduleFailure("load", "custom command Loader.Error")
        }
    }

    onSettingsChanged: {
        root.safeConfigure(widgetLoader.item)
        root.safeConfigure(qmlLoader.item)
        root.safeConfigure(commandLoader.item)
    }

    property Connections pluginChangeConnection: Connections {
        target: root.pluginRegistry
        function onLocalPluginChanged(changedPluginId) {
            if (String(changedPluginId || "") === root.pluginId) root.reload()
        }
    }

    Rectangle {
        visible: root.popoutActive
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 2
        color: Theme.accent
        z: 20
    }

    onBarChanged: {
        if (root.bar) root.registerWithBar()
    }

    Component.onCompleted: root.registerWithBar()
    Component.onDestruction: root.unregisterFromBar()
}
