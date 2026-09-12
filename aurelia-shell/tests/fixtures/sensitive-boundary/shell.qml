import QtQuick
import Quickshell
import Quickshell.Io

// T15 fixture. It exercises trusted capability stamping and self-only service
// lookup without creating or reading any credential-bearing service state.
ShellRoot {
    id: root

    readonly property string registrySource: Quickshell.env("AURELIA_SENSITIVE_REGISTRY_SOURCE") || ""
    readonly property string registryApiSource: Quickshell.env("AURELIA_SENSITIVE_REGISTRY_API_SOURCE") || ""
    readonly property string shellApiSource: Quickshell.env("AURELIA_SENSITIVE_SHELL_API_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_SENSITIVE_RESULT") || ""
    readonly property var registryApiComponent: Qt.createComponent(root.registryApiSource)
    readonly property var shellApiComponent: Qt.createComponent(root.shellApiSource)
    property var registry: null
    property var registryApi: null
    property var shellApi: null
    property bool evaluated: false

    QtObject {
        id: fakeShellConfig
        property var config: ({version: 1, plugins: [], bar: {layout: {left: [], center: [], right: []}}})
    }

    Loader {
        id: registryLoader
        source: root.registrySource
        onLoaded: {
            item.shellConfig = fakeShellConfig
            root.registry = item
            Qt.callLater(root.tryEvaluate)
        }
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

    function manifest(id, capabilities) {
        var value = {
            schemaVersion: 1,
            id: id,
            name: "Fixture " + id,
            version: "1.0.0",
            description: "Sensitive boundary fixture",
            kinds: ["service"],
            entryPoints: {service: "Service.qml"}
        }
        if (capabilities !== undefined) value.aurelia = {capabilities: capabilities}
        return value
    }

    function writeResult(value) {
        if (root.evaluated || root.resultPath === "") return
        root.evaluated = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    function tryEvaluate() {
        if (root.evaluated || !root.registry) return
        var first = root.registry.validateManifest(
            root.manifest("aurelia.secure", ["authentication", "polkit"]), "/tmp/aurelia.secure", true)
        var foreign = root.registry.validateManifest(
            root.manifest("acme.service", ["authentication"]), "/tmp/acme.service", false)
        var ordinary = root.registry.validateManifest(
            root.manifest("acme.ordinary"), "/tmp/acme.ordinary", false)
        root.registry.installedPlugins = {"aurelia.secure": first, "acme.ordinary": ordinary}

        var publicRegistry = root.registryApiComponent.createObject(null, {
            pluginId: "acme.ordinary",
            manifest: ordinary,
            enabled: true,
            registryRevision: root.registry.registryRevision
        })
        var sensitiveService = {secret: "private"}
        var scopedShell = root.shellApiComponent.createObject(null, {
            pluginId: "acme.ordinary",
            _serviceLookup: function() { return sensitiveService },
            _summon: function(payload) { return true },
            _hide: function() { return true },
            _toggle: function(payload) { return true },
            _isOpen: function() { return false },
            _settingsFor: function(selector) { return ({}) },
            _updateSettings: function(settings, selector) { return true },
            _resetSettings: function(selector) { return true }
        })
        root.registryApi = publicRegistry
        root.shellApi = scopedShell

        var publicManifest = publicRegistry.installedPlugins["acme.ordinary"]
        publicManifest.name = "mutated locally"
        var detachedManifest = ordinary.name === "Fixture acme.ordinary"
        var ownService = scopedShell.serviceFor("acme.ordinary")
        var foreignService = scopedShell.serviceFor("aurelia.secure")
        var ownUpdate = scopedShell.updateEntryInline("acme.ordinary", {}, {})
        var foreignUpdate = scopedShell.updateEntryInline("aurelia.secure", {}, {})
        var firstHasAuth = root.registry.hasTrustedCapability("aurelia.secure", "authentication")
        var firstHasPolkit = root.registry.hasTrustedCapability("aurelia.secure", "polkit")
        var ordinaryHasAuth = root.registry.hasTrustedCapability("acme.ordinary", "authentication")

        publicRegistry.enabled = false
        var disabledState = !publicRegistry.isEnabled("acme.ordinary") &&
            publicRegistry.resolveEnabledId("acme.ordinary") === "" &&
            publicRegistry.entryPointUrl(publicManifest, "service") === ""
        root.registry.registryRevision++
        var reloadStampStable = first.__hostCapabilities.length === 2 &&
            ordinary.__hostCapabilities.length === 0

        root.writeResult({
            firstStamped: first !== null && first.__hostCapabilities !== undefined,
            firstHasAuth: firstHasAuth,
            firstHasPolkit: firstHasPolkit,
            foreignRejected: foreign === null,
            ordinaryHasEmptyStamp: ordinary !== null && ordinary.__hostCapabilities.length === 0,
            ordinaryHasAuth: ordinaryHasAuth,
            publicManifestSanitized: publicManifest.__sourceDir === undefined &&
                publicManifest.__isFirstParty === undefined &&
                publicManifest.__hostCapabilities === undefined,
            detachedManifest: detachedManifest,
            ownServiceVisible: ownService && ownService.secret === "private",
            foreignServiceHidden: foreignService === null,
            ownUpdate: ownUpdate,
            foreignUpdate: foreignUpdate,
            disabledState: disabledState,
            reloadStampStable: reloadStampStable
        })
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
