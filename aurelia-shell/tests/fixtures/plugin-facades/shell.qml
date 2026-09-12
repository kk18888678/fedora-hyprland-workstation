import QtQuick
import Quickshell
import Quickshell.Io

// T14 fixture. It constructs the real PluginHost with test-local Components
// and verifies that a third-party target receives only detached, scoped APIs.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_PLUGIN_FACADE_RESULT") || ""
    readonly property string hostSource: Quickshell.env("AURELIA_PLUGIN_FACADE_HOST_SOURCE") || ""
    readonly property string registryApiSource: Quickshell.env("AURELIA_PLUGIN_FACADE_REGISTRY_SOURCE") || ""
    readonly property string shellApiSource: Quickshell.env("AURELIA_PLUGIN_FACADE_SHELL_SOURCE") || ""
    readonly property string barApiSource: Quickshell.env("AURELIA_PLUGIN_FACADE_BAR_SOURCE") || ""
    readonly property string widgetRegistryApiSource: Quickshell.env("AURELIA_PLUGIN_FACADE_WIDGET_SOURCE") || ""
    readonly property string appLibraryApiSource: Quickshell.env("AURELIA_PLUGIN_FACADE_APP_SOURCE") || ""
    readonly property string barSlotSource: Quickshell.env("AURELIA_PLUGIN_FACADE_SLOT_SOURCE") || ""
    readonly property string widgetSource: Quickshell.env("AURELIA_PLUGIN_FACADE_WIDGET_ENTRY_SOURCE") || ""
    readonly property var registryApiComponent: Qt.createComponent(root.registryApiSource)
    readonly property var shellApiComponent: Qt.createComponent(root.shellApiSource)
    readonly property var barApiComponent: Qt.createComponent(root.barApiSource)
    readonly property var barWidgetRegistryApiComponent: Qt.createComponent(root.widgetRegistryApiSource)
    readonly property var appLibraryApiComponent: Qt.createComponent(root.appLibraryApiSource)
    property var host: null
    property var target: null
    property bool evaluated: false

    QtObject {
        id: fakeShellConfig

        property var config: ({
            bar: {
                position: "top",
                layout: {left: [], center: [{id: "third.widget"}], right: []}
            }
        })

        function settingsForEntry(id, selector) {
            return {format: "default", preserved: true}
        }

        function updateEntryInline(id, settings, selector) {
            return id === "third.widget"
        }

        function resetEntryInline(id, selector) {
            return id === "third.widget"
        }
    }

    QtObject {
        id: fakeRegistry

        property var shellConfig: fakeShellConfig
        property var pluginIds: []
        property var installedPlugins: ({
            "third.widget": {
                id: "third.widget",
                name: "Third Widget",
                version: "1.0.0",
                description: "Third-party fixture",
                kinds: ["bar-widget", "menu"],
                entryPoints: {barWidget: "Widget.qml", menu: "Menu.qml"},
                barWidget: {
                    displayName: "Third Widget",
                    description: "Fixture widget",
                    category: "Testing",
                    allowMultiple: false
                },
                __sourceDir: "/private/third.widget",
                __isFirstParty: false,
                __hostCapabilities: ["should-not-leak"]
            }
        })
        property int registryRevision: 1
        property int runtimeFailureRevision: 1
        property bool enabledState: true
        signal pluginsChanged()
        signal localPluginChanged(string pluginId)
        signal pluginFailureRecorded(string pluginId, string kind, string phase,
                                     string sourcePath, string entryPoint, string detail)

        function isKnown(id) {
            return installedPlugins[id] !== undefined
        }

        function isEnabled(id) {
            return enabledState && id === "third.widget"
        }

        function primaryKind(id) {
            return "menu"
        }

        function hasActiveRuntimeFailure(id, kind) {
            return false
        }

        function entryPointUrl(id, kind) {
            return id === "third.widget"
                ? (kind === "bar-widget" ? root.widgetSource : "file:///private/third.widget/Menu.qml")
                : ""
        }

        function settingsForEntry(id, selector) {
            return fakeShellConfig.settingsForEntry(id, selector)
        }

        function updateEntryInline(id, settings, selector) {
            return fakeShellConfig.updateEntryInline(id, settings, selector)
        }

        function resetEntryInline(id, selector) {
            return fakeShellConfig.resetEntryInline(id, selector)
        }
    }

    QtObject {
        id: fakeBarWidgetRegistry

        property int revision: 4
        property var widgets: ({
            "third.widget": {
                id: "third.widget",
                name: "Third Widget",
                version: "1.0.0",
                description: "Third-party fixture",
                barWidget: {
                    displayName: "Third Widget",
                    description: "Fixture widget",
                    category: "Testing",
                    allowMultiple: false
                }
            }
        })
    }

    QtObject {
        id: fakeAppLibrary

        function appRows(query) {
            return [{id: "app:fixture.desktop", label: "Fixture", query: query}]
        }

        function iconSource(icon) {
            return "file:///icons/" + icon + ".png"
        }
    }

    QtObject {
        id: fakeBar

        property bool barHidden: false
        property int barSize: 26
        property string position: "top"
        property bool vertical: false
        property string activePopoutId: ""

        function callWidget(id, method, argument) {
            return "not-loaded"
        }

        function requestPopout(owner, id) {
            activePopoutId = String(id || "")
        }

        function releasePopout(owner) {
            activePopoutId = ""
        }

        function registerWidgetSlot(slot) {
            return true
        }

        function unregisterWidgetSlot(slot) {
            return true
        }
    }

    Loader {
        id: hostLoader
        source: root.hostSource
        onLoaded: {
            item.registry = fakeRegistry
            item.appLibrary = fakeAppLibrary
            item.barWidgetRegistry = fakeBarWidgetRegistry
            item.instances = ({"aurelia.bar": fakeBar})
            item.registryApiComponent = root.registryApiComponent
            item.shellApiComponent = root.shellApiComponent
            item.barApiComponent = root.barApiComponent
            item.barWidgetRegistryApiComponent = root.barWidgetRegistryApiComponent
            item.appLibraryApiComponent = root.appLibraryApiComponent
            root.host = item
            root.target = thirdPartyTarget
            item.configurePluginTarget("third.widget", thirdPartyTarget, {})
            Qt.callLater(root.tryEvaluate)
        }
    }

    Loader {
        id: barSlotLoader
        source: root.barSlotSource
        onLoaded: {
            item.pluginId = "third.widget"
            item.pluginRegistry = fakeRegistry
            item.barWidgetRegistry = fakeBarWidgetRegistry
            item.bar = fakeBar
            item.pluginHost = root.host
            item.settings = ({format: "fixture"})
        }
    }

    onHostChanged: if (barSlotLoader.item) barSlotLoader.item.pluginHost = root.host

    QtObject {
        id: thirdPartyTarget

        property var shell: null
        property var pluginRegistry: null
        property var bar: null
        property var barWidgetRegistry: null
        property var appLibrary: null
        property var manifest: null
        property var shellConfig: null
        property var settings: ({})
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    function writeResult(value) {
        if (root.evaluated || root.resultPath === "") return
        root.evaluated = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    function tryEvaluate() {
        if (root.evaluated || !root.host || !root.target || !barSlotLoader.item ||
            !barSlotLoader.item.widgetItem) {
            if (!root.evaluated) Qt.callLater(root.tryEvaluate)
            return
        }
        root.host.configurePluginTarget("third.widget", thirdPartyTarget, {})

        var publicManifest = thirdPartyTarget.pluginRegistry.installedPlugins["third.widget"]
        var publicMetadata = thirdPartyTarget.barWidgetRegistry.metadataFor("third.widget")
        publicMetadata.category = "mutated-locally"
        var selfRows = thirdPartyTarget.appLibrary.appRows("fix")
        selfRows[0].label = "mutated-locally"

        var selfUpdate = thirdPartyTarget.shell.updateEntryInline("third.widget", {format: "new"}, {})
        var foreignUpdate = thirdPartyTarget.shell.updateEntryInline("foreign.widget", {format: "bad"}, {})
        var selfSummon = thirdPartyTarget.shell.summon("third.widget", "{}")
        var foreignSummon = thirdPartyTarget.shell.summon("foreign.widget", "{}")
        var selfEntryPoint = thirdPartyTarget.pluginRegistry.entryPointUrl(publicManifest, "bar-widget")
        var foreignEntryPoint = thirdPartyTarget.pluginRegistry.entryPointUrl({id: "foreign.widget"}, "bar-widget")
        var foreignRequest = thirdPartyTarget.bar.requestPopout("foreign.widget")
        var appRowsAfterMutation = thirdPartyTarget.appLibrary.appRows("fix")
        var snapshotCategory = thirdPartyTarget.barWidgetRegistry.metadataFor("third.widget").category
        var widgetTarget = barSlotLoader.item.widgetItem
        var publicBarConfig = thirdPartyTarget.shell.barConfig
        publicBarConfig.position = "left"
        var barForeignRequest = widgetTarget.bar.requestPopout("foreign.widget")
        var barOwnRequest = widgetTarget.bar.requestPopout("third.widget")
        widgetTarget.bar.releasePopout("third.widget")

        var rawShellConfig = thirdPartyTarget.shellConfig
        fakeRegistry.enabledState = false
        root.host.syncScopedFacades()
        var revokedAfterDisable = Object.keys(root.host.scopedShellApis).length === 0 &&
            Object.keys(root.host.scopedRegistryApis).length === 0 &&
            Object.keys(root.host.scopedBarApis).length === 0

        fakeRegistry.enabledState = true
        root.host.configurePluginTarget("third.widget", thirdPartyTarget, {})
        fakeRegistry.installedPlugins["third.widget"].kinds = ["menu"]
        root.host.syncScopedFacades()
        var revokedAfterProfileChange = Object.keys(root.host.scopedShellApis).length === 0 &&
            Object.keys(root.host.scopedRegistryApis).length === 0

        root.writeResult({
            publicManifestHasSource: publicManifest.__sourceDir !== undefined,
            publicManifestHasPartyMarker: publicManifest.__isFirstParty !== undefined,
            publicManifestHasCapabilityStamp: publicManifest.__hostCapabilities !== undefined,
            rawShellConfigHidden: rawShellConfig === null,
            selfUpdate: selfUpdate,
            foreignUpdate: foreignUpdate,
            selfSummon: selfSummon,
            foreignSummon: foreignSummon,
            selfEntryPoint: selfEntryPoint,
            foreignEntryPoint: foreignEntryPoint,
            foreignRequest: foreignRequest,
            publicBarConfigDetached: fakeShellConfig.config.bar.position === "top" &&
                publicBarConfig.position === "left",
            barScalarState: thirdPartyTarget.bar.barSize === 26 &&
                thirdPartyTarget.bar.position === "top" && thirdPartyTarget.bar.vertical === false,
            barForeignRequest: barForeignRequest,
            barOwnRequest: barOwnRequest,
            barWidgetLoaded: widgetTarget !== null,
            barWidgetShellFacade: widgetTarget.shell !== null && widgetTarget.shell.pluginId === "third.widget",
            barWidgetRegistryFacade: widgetTarget.barWidgetRegistry !== null &&
                typeof widgetTarget.barWidgetRegistry.availableIds === "function",
            barWidgetPluginRegistryScoped: widgetTarget.pluginRegistry !== null &&
                widgetTarget.pluginRegistry.isKnown("third.widget") &&
                !widgetTarget.pluginRegistry.isKnown("foreign.widget"),
            barWidgetManifestSanitized: widgetTarget.manifest.__sourceDir === undefined &&
                widgetTarget.manifest.__isFirstParty === undefined,
            barWidgetShellConfigHidden: widgetTarget.shellConfig === null,
            selfRowLabel: appRowsAfterMutation[0].label,
            snapshotCategory: snapshotCategory,
            revokedAfterDisable: revokedAfterDisable,
            revokedAfterProfileChange: revokedAfterProfileChange,
            shellFacadeCount: Object.keys(root.host.scopedShellApis).length,
            registryFacadeCount: Object.keys(root.host.scopedRegistryApis).length
        })
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
