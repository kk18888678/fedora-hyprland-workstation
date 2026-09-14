import QtQuick
import Quickshell
import "../../theme"
import "../../services"

// A single bar module slot. Registered manifest widgets, reviewed user QML
// modules, and argv-based command modules share one placement boundary so the
// bar does not need to know each module's implementation.
Item {
    id: root

    property var bar: null
    property var barPanel: null
    property var shell: null
    property var pluginRegistry: null
    property var barWidgetRegistry: null
    property var pluginHost: null
    property string aureliaPath: ""
    property string pluginId: ""
    property var settings: ({})
    property bool active: true
    property bool registered: false
    property bool reloading: false
    property string instanceId: pluginId
    property string region: ""
    PluginSourceResolver { id: sourceResolver }
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHome: {
        var override = Quickshell.env("XDG_CONFIG_HOME") || ""
        return override.charAt(0) === "/" && override !== "/" ? override : root.home + "/.config"
    }
    readonly property string customModulesRoot: root.configHome + "/aurelia/bar/modules"
    readonly property string customType: root.resolveCustomType()
    readonly property bool customQml: root.customType === "qml"
    readonly property bool customCommand: root.customType === "command"
    readonly property var pluginSource: root.sourceDescriptorForLoader()

    readonly property var pluginManifest: barWidgetRegistry && typeof barWidgetRegistry.manifestFor === "function"
        ? barWidgetRegistry.manifestFor(pluginId)
        : (pluginRegistry && pluginRegistry.isKnown(pluginId) ? pluginRegistry.installedPlugins[pluginId] : null)
    readonly property bool available: {
        var failureRevision = pluginRegistry ? pluginRegistry.runtimeFailureRevision : 0
        var widgetRevision = barWidgetRegistry ? barWidgetRegistry.revision : 0
        if (barWidgetRegistry && typeof barWidgetRegistry.hasWidget === "function" &&
            !barWidgetRegistry.hasWidget(pluginId)) return false
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
    readonly property bool popoutActive: root.bar && root.bar.activePopoutId === root.instanceId
    readonly property bool vertical: root.bar ? root.bar.vertical === true : false
    readonly property int barSize: root.bar && root.bar.barSize ? root.bar.barSize : 26
    readonly property bool dragSource: root.bar && root.bar.widgetDragSource === root

    function fileUrl(value) {
        return sourceResolver.fileUrl(value)
    }

    function sourceDescriptorForLoader() {
        var failureRevision = pluginRegistry ? pluginRegistry.runtimeFailureRevision : 0
        var widgetRevision = barWidgetRegistry ? barWidgetRegistry.revision : 0
        if (root.customQml) {
            var customPath = root.safeCustomSource()
            var customUrl = customPath !== "" ? sourceResolver.fileUrl(customPath) : ""
            return {
                valid: customUrl !== "",
                id: root.pluginId,
                kind: "bar-widget",
                sourceRoot: root.customModulesRoot,
                relativeEntryPoint: "",
                sourcePath: customPath,
                url: customUrl,
                error: customUrl === "" ? "custom QML source is invalid" : ""
            }
        }
        if (barWidgetRegistry && typeof barWidgetRegistry.sourceDescriptorFor === "function")
            return barWidgetRegistry.sourceDescriptorFor(root.pluginId)
        if (pluginRegistry && typeof pluginRegistry.sourceDescriptor === "function")
            return pluginRegistry.sourceDescriptor(root.pluginId, "bar-widget")
        var legacyUrl = pluginRegistry && typeof pluginRegistry.entryPointUrl === "function"
            ? String(pluginRegistry.entryPointUrl(root.pluginId, "bar-widget") || "") : ""
        return {
            valid: legacyUrl !== "",
            id: root.pluginId,
            kind: "bar-widget",
            sourceRoot: "",
            relativeEntryPoint: "",
            sourcePath: "",
            url: legacyUrl,
            manifestPath: "",
            error: legacyUrl === "" ? "bar-widget source is unavailable" : ""
        }
    }

    implicitWidth: visible && widgetItem
        ? (root.vertical ? root.barSize : Math.max(0, Number(widgetItem.implicitWidth || 0)))
        : 0
    implicitHeight: visible && widgetItem
        ? (root.vertical ? Math.max(1, Number(widgetItem.implicitHeight || 0)) : root.barSize)
        : 0
    visible: active && available && widgetItem !== null
    clip: true

    function configure(target) {
        if (!target) return
        if (root.pluginHost && typeof root.pluginHost.configurePluginTarget === "function") {
            root.pluginHost.configurePluginTarget(root.pluginId, target, {
                bar: root.bar,
                barAnchorItem: root,
                instanceId: root.instanceId,
                ownerObject: root,
                settings: root.settings
            })
            return
        }
        if ("bar" in target) target.bar = root.bar
        if ("barAnchorItem" in target) target.barAnchorItem = root
        if ("shell" in target) target.shell = root.shell
        if ("aureliaPath" in target) target.aureliaPath = root.aureliaPath
        if ("moduleName" in target) target.moduleName = root.pluginId
        if ("settings" in target) target.settings = root.settings || ({})
        if ("manifest" in target) target.manifest = root.pluginManifest || ({})
        if ("pluginRegistry" in target) target.pluginRegistry = root.pluginRegistry
        if ("barWidgetRegistry" in target) target.barWidgetRegistry = root.barWidgetRegistry
    }

    function failureSource() {
        try {
            if (root.pluginSource && root.pluginSource.sourcePath) return String(root.pluginSource.sourcePath)
            if (root.customCommand) return Qt.resolvedUrl("CustomCommandBarWidget.qml")
            if (root.pluginSource && root.pluginSource.url) return String(root.pluginSource.url)
        } catch (e) {
            console.warn("[BAR] widget_source_read_failed id=" + root.pluginId)
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
            console.warn("[BAR] widget_failure_detail_unavailable id=" + root.pluginId)
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

    function loaderErrorDetail(loader, fallback) {
        var detail = ""
        try {
            if (loader && typeof loader.errorString === "function") detail = String(loader.errorString() || "")
        } catch (error) {
            console.warn("[BAR] loader_error_detail_unavailable id=" + root.pluginId)
            detail = ""
        }
        return detail !== "" ? detail : String(fallback || "Loader.Error")
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

    function refreshSettings() {
        root.safeConfigure(widgetLoader.item)
        root.safeConfigure(qmlLoader.item)
        root.safeConfigure(commandLoader.item)
        var target = root.widgetItem
        if (!target) return
        try {
            if (typeof target.aureliaSettingsChanged === "function") target.aureliaSettingsChanged()
        } catch (error) {
            root.reportFailure("settings", error)
        }
    }

    function scheduleSettingsRefresh() {
        settingsRefreshTimer.restart()
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

    DragHandler {
        id: reorderHandler
        target: null
        enabled: root.visible && root.width > 0 && root.height > 0 && root.barPanel !== null &&
            typeof root.barPanel.beginWidgetDrag === "function"
        acceptedButtons: Qt.LeftButton
        dragThreshold: root.bar && root.bar.barDragThreshold !== undefined
            ? Number(root.bar.barDragThreshold) : 4
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        onActiveChanged: {
            if (!root.barPanel) return
            if (active) {
                root.barPanel.beginWidgetDrag(root, centroid.scenePosition)
            } else if (typeof root.barPanel.endWidgetDrag === "function") {
                root.barPanel.endWidgetDrag(root)
            }
        }

        onCentroidChanged: {
            if (active && root.barPanel && typeof root.barPanel.updateWidgetDrag === "function")
                root.barPanel.updateWidgetDrag(root, centroid.scenePosition)
        }

        onCanceled: {
            if (root.barPanel && typeof root.barPanel.cancelWidgetDrag === "function")
                root.barPanel.cancelWidgetDrag(root)
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
        opacity: root.dragSource ? 0.22 : 1.0
        active: root.active && root.available && !root.reloading &&
            (root.pluginManifest === null || root.pluginManifest.__isFirstParty !== false || root.pluginHost !== null)
        source: root.pluginSource && root.pluginSource.valid === true
            ? String(root.pluginSource.url || "") : ""

        onLoaded: root.handleLoaded(item)
        onStatusChanged: {
            if (status === Loader.Error)
                root.scheduleFailure("load", root.loaderErrorDetail(widgetLoader, "registered widget Loader.Error"))
        }
    }

    Loader {
        id: qmlLoader
        anchors.fill: parent
        opacity: root.dragSource ? 0.22 : 1.0
        active: root.customQml && !root.reloading
        source: root.customQml ? root.fileUrl(root.safeCustomSource()) : ""
        onLoaded: root.handleLoaded(item)
        onStatusChanged: {
            if (status === Loader.Error)
                root.scheduleFailure("load", root.loaderErrorDetail(qmlLoader, "custom QML Loader.Error"))
        }
    }

    Loader {
        id: commandLoader
        anchors.fill: parent
        opacity: root.dragSource ? 0.22 : 1.0
        active: root.customCommand && !root.reloading
        source: Qt.resolvedUrl("CustomCommandBarWidget.qml")
        onLoaded: root.handleLoaded(item)
        onStatusChanged: {
            if (status === Loader.Error)
                root.scheduleFailure("load", root.loaderErrorDetail(commandLoader, "custom command Loader.Error"))
        }
    }

    // A Loader can destroy a slot while the host is rebuilding a bar surface.
    // Keep the deferred settings push owned by this component so destruction
    // cancels it instead of invoking an unbound function in an invalid QML
    // context.
    Timer {
        id: settingsRefreshTimer
        interval: 0
        repeat: false
        onTriggered: root.refreshSettings()
    }

    onSettingsChanged: root.scheduleSettingsRefresh()
    onPluginHostChanged: root.scheduleSettingsRefresh()

    property Connections pluginChangeConnection: Connections {
        target: root.pluginRegistry
        function onLocalPluginChanged(changedPluginId) {
            if (String(changedPluginId || "") === root.pluginId) root.reload()
        }
    }

    Rectangle {
        visible: root.dragSource
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.min(Theme.radiusSm, height / 2)
        color: "transparent"
        border.color: root.bar && root.bar.barForeground !== undefined
            ? root.bar.barForeground : Theme.text
        border.width: 1
        opacity: root.bar && root.bar.transparent ? 0.55 : 0.32
        z: 20
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
