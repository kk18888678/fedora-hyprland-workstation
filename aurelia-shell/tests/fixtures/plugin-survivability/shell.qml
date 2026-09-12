import QtQuick
import Quickshell
import Quickshell.Io

// Disposable T02A runtime fixture. It uses a fake registry so discovery and
// persistence are not involved; the real PluginHost Loader and callback
// boundaries are exercised in a separate QuickShell process.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_PLUGIN_SURVIVABILITY_RESULT") || ""
    readonly property string hostSource: Quickshell.env("AURELIA_PLUGIN_HOST_SOURCE") || ""
    readonly property string barSlotSource: Quickshell.env("AURELIA_BAR_SLOT_SOURCE") || ""
    property bool finishing: false
    property string firstCallbackResult: ""
    property string firstOpenResult: ""
    property string firstCloseResult: ""
    property string firstToggleResult: ""
    property string firstCallResult: ""
    property string firstWidgetResult: ""

    QtObject {
        id: fakeShellConfig
        property var config: ({ version: 1, bar: { id: "replacement.bar" } })
    }

    QtObject {
        id: fakeShellApi
    }

    QtObject {
        id: fakeRegistry

        property QtObject shellConfig: fakeShellConfig
        property string packageRoot: Qt.resolvedUrl(".")
        property int registryRevision: 1
        property int runtimeFailureRevision: 0
        property var runtimeFailures: ({})
        property var failureHistory: ({})
        signal localPluginChanged(string changedPluginId)
        property var installedPlugins: ({
            "bad.callback": {
                name: "Bad callback",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "BadCallback.qml" },
                keepLoaded: true
            },
            "bad.open": {
                name: "Bad open",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "BadOpen.qml" },
                keepLoaded: true
            },
            "bad.close": {
                name: "Bad close",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "BadClose.qml" },
                keepLoaded: true
            },
            "bad.toggle": {
                name: "Bad toggle",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "BadToggle.qml" },
                keepLoaded: true
            },
            "bad.call": {
                name: "Bad IPC call",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "BadCall.qml" },
                keepLoaded: true
            },
            "bad.init": {
                name: "Bad initialization",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "BadInit.qml" },
                keepLoaded: true
            },
            "bad.load": {
                name: "Bad load",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "BadLoad.qml" },
                keepLoaded: true
            },
            "bad.service": {
                name: "Bad service",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["service"],
                entryPoints: { service: "BadService.qml" },
                keepLoaded: true
            },
            "bad.missing": {
                name: "Bad missing entry point",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "Missing.qml" },
                keepLoaded: true
            },
            "healthy.panel": {
                name: "Healthy panel",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "HealthyPanel.qml" },
                keepLoaded: true
            },
            "healthy.service": {
                name: "Healthy service",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["service"],
                entryPoints: { service: "HealthyService.qml" },
                keepLoaded: true
            },
            "replacement.bar": {
                name: "Broken replacement bar",
                version: "0.0.1",
                description: "Fixture",
                kinds: ["bar"],
                entryPoints: { bar: "BadBar.qml" },
                keepLoaded: true
            }
        })

        readonly property var pluginIds: [
            "bad.callback",
            "bad.open",
            "bad.close",
            "bad.toggle",
            "bad.call",
            "bad.init",
            "bad.load",
            "bad.missing",
            "bad.service",
            "healthy.panel",
            "healthy.service",
            "replacement.bar"
        ]

        signal pluginsChanged()
        signal scanFinished()
        signal pluginFailureRecorded(string pluginId, string kind, string phase, string sourcePath, string entryPoint, string detail)

        function isKnown(id) {
            return installedPlugins[id] !== undefined
        }

        function isEnabled(id) {
            return isKnown(id)
        }

        function primaryKind(id) {
            return isKnown(id) ? installedPlugins[id].kinds[0] : ""
        }

        function entryPointUrl(id, kind) {
            if (!isKnown(id) || !installedPlugins[id].entryPoints[kind]) return ""
            return Qt.resolvedUrl(installedPlugins[id].entryPoints[kind])
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
            return !!failure && failure.quarantined === true && failure.generation === registryRevision
        }

        function recordRuntimeFailure(id, kind, phase, sourcePath, entryPoint, detail) {
            var next = {}
            for (var key in runtimeFailures) next[key] = runtimeFailures[key]
            var failureKey = runtimeFailureKey(id, kind)
            var previous = next[failureKey]
            var history = {}
            for (var historyKey in failureHistory) history[historyKey] = failureHistory[historyKey]
            history[failureKey] = (history[failureKey] || 0) + 1
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
                attempts: previous ? previous.attempts + 1 : 1,
                quarantined: true,
                retryState: "requires-explicit-reload"
            }
            runtimeFailures = next
            runtimeFailureRevision++
            pluginFailureRecorded(id, kind, phase, sourcePath, entryPoint, detail)
            return true
        }

        function clearRuntimeFailure(id, kind) {
            var next = {}
            var changed = false
            var prefix = String(id || "") + "::"
            for (var key in runtimeFailures) {
                if (key.indexOf(prefix) === 0 &&
                    (kind === undefined || key === runtimeFailureKey(id, kind))) changed = true
                else next[key] = runtimeFailures[key]
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
                result.push({
                    id: id,
                    name: installedPlugins[id].name,
                    version: installedPlugins[id].version,
                    description: installedPlugins[id].description,
                    icon: "",
                    kinds: installedPlugins[id].kinds,
                    firstParty: true,
                    enabled: true,
                    keepLoaded: true,
                    failures: []
                })
            }
            return result
        }
    }

    QtObject {
        id: widgetRegistry

        property int registryRevision: 1
        property int runtimeFailureRevision: 0
        property var runtimeFailures: ({})
        property var failureHistory: ({})
        signal localPluginChanged(string changedPluginId)
        property var installedPlugins: ({
            "bad.widget": {
                name: "Bad widget",
                version: "0.0.1",
                kinds: ["bar-widget"],
                entryPoints: { "bar-widget": "BadWidget.qml" }
            },
            "bad.widget.load": {
                name: "Bad widget load",
                version: "0.0.1",
                kinds: ["bar-widget"],
                entryPoints: { "bar-widget": "BadWidgetLoad.qml" }
            },
            "healthy.widget": {
                name: "Healthy widget",
                version: "0.0.1",
                kinds: ["bar-widget"],
                entryPoints: { "bar-widget": "HealthyWidget.qml" }
            }
        })

        function isKnown(id) {
            return installedPlugins[id] !== undefined
        }

        function isEnabled(id) {
            return isKnown(id)
        }

        function entryPointUrl(id, kind) {
            if (!isKnown(id) || !installedPlugins[id].entryPoints[kind]) return ""
            return Qt.resolvedUrl(installedPlugins[id].entryPoints[kind])
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
            return !!failure && failure.quarantined === true && failure.generation === registryRevision
        }

        function recordRuntimeFailure(id, kind, phase, sourcePath, entryPoint, detail) {
            var next = {}
            for (var key in runtimeFailures) next[key] = runtimeFailures[key]
            var failureKey = runtimeFailureKey(id, kind)
            var previous = next[failureKey]
            var history = {}
            for (var historyKey in failureHistory) history[historyKey] = failureHistory[historyKey]
            history[failureKey] = (history[failureKey] || 0) + 1
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
                attempts: previous ? previous.attempts + 1 : 1,
                quarantined: true,
                retryState: "requires-explicit-reload"
            }
            runtimeFailures = next
            runtimeFailureRevision++
            return true
        }

        function clearRuntimeFailure(id, kind) {
            var next = {}
            var changed = false
            var prefix = String(id || "") + "::"
            for (var key in runtimeFailures) {
                if (key.indexOf(prefix) === 0 &&
                    (kind === undefined || key === runtimeFailureKey(id, kind))) changed = true
                else next[key] = runtimeFailures[key]
            }
            if (changed) {
                runtimeFailures = next
                runtimeFailureRevision++
            }
            return changed
        }
    }

    QtObject {
        id: barApi
        property var registeredSlots: []
        property int widgetRevision: 0

        function registerWidgetSlot(slot) {
            var next = registeredSlots.slice()
            if (next.indexOf(slot) === -1) {
                next.push(slot)
                registeredSlots = next
            }
        }

        function unregisterWidgetSlot(slot) {
            var next = []
            for (var i = 0; i < registeredSlots.length; i++)
                if (registeredSlots[i] !== slot) next.push(registeredSlots[i])
            registeredSlots = next
        }

        function bumpWidgetRevision() {
            widgetRevision++
        }
    }

    Loader {
        id: host
        source: root.hostSource
        onLoaded: {
            item.registry = fakeRegistry
            item.shellApi = fakeShellApi
            item.appLibrary = fakeShellApi
        }
    }

    Loader {
        id: healthyWidgetSlot
        source: root.barSlotSource
        onLoaded: {
            item.pluginId = "healthy.widget"
            item.pluginRegistry = widgetRegistry
            item.bar = barApi
        }
    }

    Loader {
        id: badWidgetSlot
        source: root.barSlotSource
        onLoaded: {
            item.pluginId = "bad.widget"
            item.pluginRegistry = widgetRegistry
            item.bar = barApi
        }
    }

    Loader {
        id: badWidgetLoadSlot
        source: root.barSlotSource
        onLoaded: {
            item.pluginId = "bad.widget.load"
            item.pluginRegistry = widgetRegistry
            item.bar = barApi
        }
    }

    IpcHandler {
        id: fixtureIpc
        target: "aurelia-survivability-fixture"

        function ping(): string {
            return host.item ? "ok" : "not-ready"
        }

        function listPlugins(): string {
            return host.item ? JSON.stringify(host.item.summaries()) : "[]"
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

    function exerciseFailures() {
        if (root.finishing || !host.item) return
        root.firstCallbackResult = host.item.open("bad.callback", "{}")
        root.firstOpenResult = host.item.open("bad.open", "{}")
        root.firstCloseResult = host.item.close("bad.close")
        root.firstToggleResult = host.item.toggle("bad.toggle", "{}")
        root.firstCallResult = host.item.call("bad.call", "ipcAction", "{}")
        root.firstWidgetResult = badWidgetSlot.item
            ? badWidgetSlot.item.invoke("open", "{}")
            : "not-loaded"
        // This is the explicit retry boundary. A bad plugin must remain
        // quarantined until this operation, then be allowed one new attempt.
        host.item.beginReload({ "bad.callback": true })
        host.item.finishReload()
        reloadCheck.start()
    }

    function finish() {
        if (root.finishing || root.resultPath === "") return
        root.finishing = true
        var hostItem = host.item
        var secondCallbackResult = hostItem.open("bad.callback", "{}")
        var summaries = hostItem.summaries()
        var listedPlugins = []
        try {
            listedPlugins = JSON.parse(fixtureIpc.listPlugins())
        } catch (e) {}
        var callbackFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("bad.callback", "panel")]
        var openFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("bad.open", "panel")]
        var closeFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("bad.close", "panel")]
        var toggleFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("bad.toggle", "panel")]
        var callFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("bad.call", "panel")]
        var initFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("bad.init", "panel")]
        var loadFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("bad.load", "panel")]
        var missingFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("bad.missing", "panel")]
        var serviceFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("bad.service", "service")]
        var replacementFailure = fakeRegistry.runtimeFailures[fakeRegistry.runtimeFailureKey("replacement.bar", "bar")]
        var badWidgetFailure = widgetRegistry.runtimeFailures[widgetRegistry.runtimeFailureKey("bad.widget", "bar-widget")]
        var badWidgetLoadFailure = widgetRegistry.runtimeFailures[widgetRegistry.runtimeFailureKey("bad.widget.load", "bar-widget")]
        var healthyWidget = healthyWidgetSlot.item
        var badWidget = badWidgetSlot.item
        resultFile.setText(JSON.stringify({
            hostAlive: hostItem.registry !== null,
            pingResponded: fixtureIpc.ping() === "ok",
            listPluginsResponded: summaries.length === fakeRegistry.pluginIds.length &&
                listedPlugins.length === fakeRegistry.pluginIds.length,
            healthyPanelLoaded: hostItem.itemFor("healthy.panel") !== null,
            healthyServiceLoaded: hostItem.itemFor("healthy.service") !== null,
            healthyCall: hostItem.call("healthy.panel", "health", "{}"),
            healthyStillLoaded: hostItem.itemFor("healthy.panel") !== null,
            healthyBarWidgetLoaded: !!healthyWidget && healthyWidgetSlot.item.available === true,
            healthyBarWidgetStillAvailable: healthyWidgetSlot.item.available === true,
            badWidgetResult: root.firstWidgetResult,
            badWidgetAvailableAfterFailure: !!badWidget && badWidget.available === true,
            badWidgetReported: !!badWidgetFailure,
            badWidgetLoadReported: !!badWidgetLoadFailure,
            badCallbackResult: root.firstCallbackResult,
            badOpenResult: root.firstOpenResult,
            badCloseResult: root.firstCloseResult,
            badToggleResult: root.firstToggleResult,
            badCallResult: root.firstCallResult,
            badCallbackReloadResult: secondCallbackResult,
            badCallbackReported: !!callbackFailure,
            badOpenReported: !!openFailure,
            badCloseReported: !!closeFailure,
            badToggleReported: !!toggleFailure,
            badCallReported: !!callFailure,
            badInitReported: !!initFailure,
            badLoadReported: !!loadFailure,
            badMissingReported: !!missingFailure,
            badServiceReported: !!serviceFailure,
            badReplacementReported: !!replacementFailure,
            activeBarFallback: hostItem.activeBarId === "aurelia.bar",
            reloadAttempts: fakeRegistry.failureHistory[fakeRegistry.runtimeFailureKey("bad.callback", "panel")] || 0,
            quarantinedLoadAttempts: fakeRegistry.failureHistory[fakeRegistry.runtimeFailureKey("bad.load", "panel")] || 0,
            failureCount: Object.keys(fakeRegistry.runtimeFailures).length + Object.keys(widgetRegistry.runtimeFailures).length
        }) + "\n")
    }

    Timer {
        interval: 1400
        running: true
        repeat: false
        onTriggered: root.exerciseFailures()
    }

    Timer {
        id: reloadCheck
        interval: 700
        repeat: false
        onTriggered: root.finish()
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
