import QtQuick
import Quickshell
import Quickshell.Io

// T08 active-bar fixture. It exercises only PluginHost selection and Loader
// fallback; no PanelWindow or live bar surface is created.
ShellRoot {
    id: root

    readonly property string hostSource: Quickshell.env("AURELIA_BAR_SELECTION_HOST_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_SELECTION_RESULT") || ""
    property bool replacementEnabled: true
    property int phase: 0
    property bool finishing: false
    property string initialActive: ""
    property bool replacementSuccess: false
    property bool brokenFallback: false
    property bool disabledFallback: false
    property bool rescanSuccess: false

    QtObject {
        id: fixtureConfig
        property var config: ({ version: 1, bar: { id: "aurelia.bar" } })
    }

    QtObject {
        id: shellApi
    }

    QtObject {
        id: fakeRegistry
        property QtObject shellConfig: fixtureConfig
        property string packageRoot: Qt.resolvedUrl(".")
        property int registryRevision: 1
        property int runtimeFailureRevision: 0
        property var runtimeFailures: ({})
        property var installedPlugins: ({
            "aurelia.bar": {
                name: "Built-in bar",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["bar"],
                entryPoints: { bar: "GoodBar.qml" },
                keepLoaded: true
            },
            "replacement.bar": {
                name: "Replacement bar",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["bar"],
                entryPoints: { bar: "GoodBar.qml" },
                keepLoaded: true
            },
            "broken.bar": {
                name: "Broken bar",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["bar"],
                entryPoints: { bar: "BadBar.qml" },
                keepLoaded: true
            }
        })
        property var pluginIds: ["aurelia.bar", "broken.bar", "replacement.bar"]

        signal pluginsChanged()
        signal pluginFailureRecorded(string pluginId, string kind, string phase, string sourcePath, string entryPoint, string detail)

        function isKnown(id) {
            return installedPlugins[id] !== undefined
        }

        function isEnabled(id) {
            return id !== "replacement.bar" || replacementEnabled
        }

        function primaryKind(id) {
            return isKnown(id) ? "bar" : ""
        }

        function entryPointUrl(id, kind) {
            if (!isKnown(id) || kind !== "bar") return ""
            return Qt.resolvedUrl(installedPlugins[id].entryPoints.bar)
        }

        function boundedFailureDetail(value) {
            return String(value || "plugin failure").substring(0, 512)
        }

        function hasActiveRuntimeFailure(id, kind) {
            var revision = runtimeFailureRevision
            var failure = runtimeFailures[String(id || "") + "::" + String(kind || "")]
            return !!failure && failure.quarantined === true && failure.generation === registryRevision
        }

        function recordRuntimeFailure(id, kind, phase, sourcePath, entryPoint, detail) {
            var next = {}
            for (var key in runtimeFailures) next[key] = runtimeFailures[key]
            next[String(id) + "::" + String(kind)] = {
                id: id,
                kind: kind,
                phase: phase,
                sourcePath: sourcePath,
                entryPoint: entryPoint,
                detail: boundedFailureDetail(detail),
                generation: registryRevision,
                quarantined: true
            }
            runtimeFailures = next
            runtimeFailureRevision++
            pluginFailureRecorded(id, kind, phase, sourcePath, entryPoint, detail)
            return true
        }

        function clearRuntimeFailure(id, kind) {
            var next = {}
            var wanted = String(id || "")
            for (var key in runtimeFailures)
                if (key !== wanted + "::" + String(kind || "")) next[key] = runtimeFailures[key]
            runtimeFailures = next
            runtimeFailureRevision++
            return true
        }
    }

    Loader {
        id: hostLoader
        source: root.hostSource
        onLoaded: {
            item.registry = fakeRegistry
            item.shellApi = shellApi
            item.appLibrary = shellApi
        }
    }

    IpcHandler {
        target: "aurelia-bar-selection-fixture"
        function ping(): bool {
            return hostLoader.item !== null
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

    function selectBar(id) {
        fixtureConfig.config = { version: 1, bar: { id: id } }
        fakeRegistry.registryRevision++
        fakeRegistry.pluginsChanged()
    }

    function fullBarCount(host) {
        var count = 0
        var ids = ["aurelia.bar", "replacement.bar", "broken.bar"]
        for (var i = 0; i < ids.length; i++) if (host.itemFor(ids[i]) !== null) count++
        return count
    }

    function step() {
        if (root.finishing || !hostLoader.item) return
        var host = hostLoader.item
        if (root.phase === 0 && host.itemFor("aurelia.bar") !== null) {
            root.initialActive = host.activeBarId
            root.phase = 1
            root.selectBar("replacement.bar")
        } else if (root.phase === 1 && host.activeBarId === "replacement.bar" &&
                   host.itemFor("replacement.bar") !== null) {
            root.replacementSuccess = true
            root.phase = 2
            root.selectBar("broken.bar")
        } else if (root.phase === 2 && host.activeBarId === "aurelia.bar" &&
                   fakeRegistry.runtimeFailures["broken.bar::bar"] !== undefined &&
                   host.itemFor("aurelia.bar") !== null) {
            root.brokenFallback = true
            root.phase = 3
            root.replacementEnabled = false
            root.selectBar("replacement.bar")
        } else if (root.phase === 3 && host.activeBarId === "aurelia.bar" &&
                   host.itemFor("replacement.bar") === null) {
            root.disabledFallback = true
            root.phase = 4
            root.replacementEnabled = true
            root.selectBar("replacement.bar")
        } else if (root.phase === 4 && host.activeBarId === "replacement.bar" &&
                   host.itemFor("replacement.bar") !== null) {
            host.beginReload()
            host.finishReload()
            root.phase = 5
        } else if (root.phase === 5 && host.activeBarId === "replacement.bar" &&
                   host.itemFor("replacement.bar") !== null) {
            root.rescanSuccess = true
            root.finish()
        }
    }

    function finish() {
        if (root.finishing || !hostLoader.item) return
        root.finishing = true
        var host = hostLoader.item
        resultFile.setText(JSON.stringify({
            hostAlive: hostLoader.item !== null,
            pingResponded: hostLoader.item !== null,
            initialBuiltIn: root.initialActive === "aurelia.bar",
            replacementSuccess: root.replacementSuccess,
            brokenFallback: root.brokenFallback,
            disabledFallback: root.disabledFallback,
            rescanSuccess: root.rescanSuccess,
            activeBarId: host.activeBarId,
            fullBarCount: root.fullBarCount(host),
            builtInLoaded: host.itemFor("aurelia.bar") !== null,
            replacementLoaded: host.itemFor("replacement.bar") !== null,
            brokenReported: fakeRegistry.runtimeFailures["broken.bar::bar"] !== undefined
        }) + "\n")
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: root.step()
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
