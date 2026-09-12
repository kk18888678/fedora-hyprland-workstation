import QtQuick
import Quickshell
import Quickshell.Io

// T24 generic runtime matrix. The fixture uses disposable Item entry points
// for each supported kind so the real PluginHost Loader and failure boundaries
// are exercised without constructing a production feature surface.
ShellRoot {
    id: root

    readonly property string hostSource: Quickshell.env("AURELIA_CONTRACT_MATRIX_HOST_SOURCE") || ""
    readonly property string fixtureRoot: Quickshell.env("AURELIA_CONTRACT_MATRIX_ROOT") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_CONTRACT_MATRIX_RESULT") || ""
    property var hostObject: null
    property bool started: false
    property bool finishing: false
    property string openResult: ""
    property string closeResult: ""
    property string callbackResult: ""
    property bool callbackQuarantined: false
    property bool callbackHealthyService: false
    property bool replacementBarFailed: false
    property bool initialKindsLoaded: false
    property var loadedEvents: []
    property var failedEvents: []
    property var reloadedEvents: []

    QtObject {
        id: fakeShellConfig
        property var config: ({version: 1, bar: {id: "matrix.bar"}})
    }

    QtObject {
        id: fakeShellApi
    }

    QtObject {
        id: fakeRegistry

        property QtObject shellConfig: fakeShellConfig
        property string packageRoot: root.fixtureRoot
        property int registryRevision: 1
        property int runtimeFailureRevision: 0
        property var runtimeFailures: ({})
        property var failureHistory: ({})
        property var installedPlugins: ({
            "aurelia.bar": {
                id: "aurelia.bar",
                name: "Built-in fallback bar",
                version: "1.0.0",
                description: "Fallback fixture",
                kinds: ["bar"],
                entryPoints: {bar: "Entry.qml"},
                keepLoaded: true,
                __isFirstParty: true
            },
            "matrix.bar": {
                id: "matrix.bar",
                name: "Replacement bar",
                version: "1.0.0",
                description: "Replacement fixture",
                kinds: ["bar"],
                entryPoints: {bar: "Entry.qml"},
                keepLoaded: true,
                __isFirstParty: true
            },
            "matrix.bar-widget": {
                id: "matrix.bar-widget",
                name: "Bar widget fixture",
                version: "1.0.0",
                description: "Bar-widget fixture",
                kinds: ["bar-widget"],
                entryPoints: {barWidget: "Entry.qml"},
                keepLoaded: true,
                __isFirstParty: true
            },
            "matrix.panel": {
                id: "matrix.panel",
                name: "Panel fixture",
                version: "1.0.0",
                description: "Panel fixture",
                kinds: ["panel"],
                entryPoints: {panel: "Entry.qml"},
                keepLoaded: true,
                __isFirstParty: true
            },
            "matrix.overlay": {
                id: "matrix.overlay",
                name: "Overlay fixture",
                version: "1.0.0",
                description: "Overlay fixture",
                kinds: ["overlay"],
                entryPoints: {overlay: "Entry.qml"},
                keepLoaded: true,
                __isFirstParty: true
            },
            "matrix.menu": {
                id: "matrix.menu",
                name: "Menu fixture",
                version: "1.0.0",
                description: "Menu fixture",
                kinds: ["menu"],
                entryPoints: {menu: "Entry.qml"},
                keepLoaded: true,
                __isFirstParty: true
            },
            "matrix.service": {
                id: "matrix.service",
                name: "Service fixture",
                version: "1.0.0",
                description: "Service fixture",
                kinds: ["service"],
                entryPoints: {service: "Entry.qml"},
                keepLoaded: true,
                __isFirstParty: true
            }
        })
        readonly property var pluginIds: [
            "aurelia.bar",
            "matrix.bar",
            "matrix.bar-widget",
            "matrix.panel",
            "matrix.overlay",
            "matrix.menu",
            "matrix.service"
        ]

        signal pluginsChanged()
        signal pluginFailureRecorded(string pluginId, string kind, string phase,
                                     string sourcePath, string entryPoint, string detail)

        function isKnown(id) {
            return installedPlugins[id] !== undefined
        }

        function isEnabled(id) {
            return isKnown(id)
        }

        function primaryKind(id) {
            var manifest = installedPlugins[id]
            if (!manifest || !Array.isArray(manifest.kinds)) return ""
            if (manifest.kinds.indexOf("service") !== -1) return "service"
            return manifest.kinds[0] || ""
        }

        function entryPointUrl(id, kind) {
            var manifest = installedPlugins[id]
            if (!manifest) return ""
            var key = kind === "bar-widget" ? "barWidget" : kind
            var entry = manifest.entryPoints[key]
            return entry ? "file://" + root.fixtureRoot + "/" + id + "/" + entry : ""
        }

        function resolveEnabledId(id) {
            return String(id || "")
        }

        function cloneSourceIdForManifest(manifest) {
            return ""
        }

        function boundedFailureDetail(value) {
            var detail = String(value || "plugin failure").replace(/\s+/g, " ").trim()
            return detail.length > 512 ? detail.substring(0, 512) + "..." : detail
        }

        function runtimeFailureKey(id, kind) {
            return String(id || "") + "::" + String(kind || "")
        }

        function hasActiveRuntimeFailure(id, kind) {
            var revision = runtimeFailureRevision
            var failure = runtimeFailures[runtimeFailureKey(id, kind)]
            return !!failure && failure.quarantined === true &&
                Number(failure.generation) === registryRevision
        }

        function recordRuntimeFailure(id, kind, phase, sourcePath, entryPoint, detail) {
            var failureKey = runtimeFailureKey(id, kind)
            var next = {}
            for (var key in runtimeFailures) next[key] = runtimeFailures[key]
            var history = {}
            for (var historyKey in failureHistory) history[historyKey] = failureHistory[historyKey]
            history[failureKey] = Number(history[failureKey] || 0) + 1
            failureHistory = history
            next[failureKey] = {
                id: id,
                kind: kind,
                phase: phase,
                sourcePath: sourcePath,
                entryPoint: entryPoint,
                detail: boundedFailureDetail(detail),
                timestamp: Date.now(),
                generation: registryRevision,
                attempts: history[failureKey],
                quarantined: true,
                retryState: "requires-explicit-reload"
            }
            runtimeFailures = next
            runtimeFailureRevision++
            pluginFailureRecorded(id, kind, phase, sourcePath, entryPoint, detail)
            return true
        }

        function clearRuntimeFailure(id, kind) {
            var prefix = String(id || "") + "::"
            var next = {}
            var changed = false
            for (var key in runtimeFailures) {
                if (key.indexOf(prefix) === 0 &&
                    (kind === undefined || kind === null || String(kind) === "" ||
                     key === runtimeFailureKey(id, kind))) {
                    changed = true
                } else {
                    next[key] = runtimeFailures[key]
                }
            }
            if (changed) {
                runtimeFailures = next
                runtimeFailureRevision++
            }
            return changed
        }

        function pluginSummaries() {
            var result = []
            for (var i = 0; i < pluginIds.length; i++) {
                var id = pluginIds[i]
                var manifest = installedPlugins[id]
                result.push({
                    id: id,
                    name: manifest.name,
                    version: manifest.version,
                    description: manifest.description,
                    icon: "",
                    kinds: manifest.kinds,
                    firstParty: true,
                    enabled: true,
                    keepLoaded: true,
                    failures: []
                })
            }
            return result
        }

        function pluginCatalog() {
            return {
                plugins: pluginSummaries(),
                rejected: [],
                scan: {state: "success", failureClass: "", rejectedCount: 0, error: ""}
            }
        }

        function settingsForEntry(id, selector) {
            return ({})
        }
    }

    Loader {
        id: hostLoader
        source: root.hostSource
        onLoaded: {
            item.registry = fakeRegistry
            item.shellApi = fakeShellApi
            item.appLibrary = fakeShellApi
            root.hostObject = item
        }
    }

    Connections {
        target: root.hostObject
        function onPluginLoaded(pluginId, kind) {
            root.loadedEvents = root.loadedEvents.concat([pluginId + "::" + kind])
        }
        function onPluginLoadFailed(pluginId, kind) {
            root.failedEvents = root.failedEvents.concat([pluginId + "::" + kind])
        }
        function onPluginReloaded(pluginId) {
            root.reloadedEvents = root.reloadedEvents.concat([pluginId])
        }
    }

    IpcHandler {
        target: "aurelia-contract-matrix"

        function ping(): bool {
            return root.hostObject !== null
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

    function writeResult(value) {
        if (root.finishing || root.resultPath === "") return
        root.finishing = true
        resultFile.setText(JSON.stringify(value) + "\n")
    }

    function kindFixturesLoaded(host) {
        var ids = ["matrix.bar", "matrix.bar-widget", "matrix.panel",
            "matrix.overlay", "matrix.menu", "matrix.service"]
        for (var i = 0; i < ids.length; i++) {
            var item = host.itemFor(ids[i])
            if (!item || item.initialized !== true) return false
        }
        return true
    }

    function start() {
        if (root.started || !root.hostObject) return
        var host = root.hostObject
        if (!root.kindFixturesLoaded(host)) {
            startTimer.restart()
            return
        }
        root.started = true
        root.initialKindsLoaded = true
        root.openResult = host.open("matrix.panel", "{}")
        root.closeResult = host.close("matrix.panel")
        root.callbackResult = host.call("matrix.panel", "explode", "{}")
        root.callbackQuarantined = fakeRegistry.hasActiveRuntimeFailure("matrix.panel", "panel") &&
            host.itemFor("matrix.panel") === null
        root.callbackHealthyService = host.itemFor("matrix.service") !== null &&
            host.itemFor("matrix.bar-widget") !== null

        host.beginReload({"matrix.panel": true})
        host.finishReload()
        host.recordFailure("matrix.bar", "bar", "load", "intentional replacement failure")
        root.replacementBarFailed = fakeRegistry.hasActiveRuntimeFailure("matrix.bar", "bar")
        finishTimer.start()
    }

    function finish() {
        if (!root.started || root.finishing || !root.hostObject) return
        var host = root.hostObject
        var summaries = host.summaries()
        var panel = host.itemFor("matrix.panel")
        var service = host.itemFor("matrix.service")
        var widget = host.itemFor("matrix.bar-widget")
        root.writeResult({
            hostStillAlive: host !== null,
            pingResponded: typeof host.itemFor === "function",
            listPluginsResponded: Array.isArray(summaries) &&
                summaries.length === fakeRegistry.pluginIds.length,
            initialKindsLoaded: root.initialKindsLoaded,
            openResult: root.openResult,
            closeResult: root.closeResult,
            callbackResult: root.callbackResult,
            callbackQuarantined: root.callbackQuarantined,
            callbackHealthyService: root.callbackHealthyService,
            reloadRestored: panel !== null && panel.initialized === true,
            reloadClearedFailure: !fakeRegistry.hasActiveRuntimeFailure("matrix.panel", "panel"),
            replacementBarFailed: root.replacementBarFailed &&
                host.itemFor("matrix.bar") === null,
            builtInBarFallback: host.activeBarId === "aurelia.bar" &&
                host.itemFor("aurelia.bar") !== null,
            healthyServiceAfterBarFailure: service !== null &&
                host.call("matrix.service", "health", "") === "healthy-matrix.service",
            healthyWidgetAfterBarFailure: widget !== null && widget.initialized === true,
            loadedEventCount: root.loadedEvents.length,
            failedEventCount: root.failedEvents.length,
            reloadedPanel: root.reloadedEvents.indexOf("matrix.panel") !== -1
        })
    }

    Timer {
        id: startTimer
        interval: 350
        repeat: false
        running: true
        onTriggered: root.start()
    }

    Timer {
        id: finishTimer
        interval: 900
        repeat: false
        onTriggered: root.finish()
    }

    Timer {
        interval: 8000
        repeat: false
        running: true
        onTriggered: Qt.quit()
    }
}
