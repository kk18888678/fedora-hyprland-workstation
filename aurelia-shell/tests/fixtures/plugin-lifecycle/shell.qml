import QtQuick
import Quickshell
import Quickshell.Io

// T07 runtime fixture for resident lifecycle, ordered summons, multi-kind
// ownership, and unload behavior. All registry state is test-local.
ShellRoot {
    id: root

    readonly property string hostSource: Quickshell.env("AURELIA_LIFECYCLE_HOST_SOURCE") || ""
    readonly property string barRegistrySource: Quickshell.env("AURELIA_LIFECYCLE_BAR_REGISTRY_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_LIFECYCLE_RESULT") || ""
    property bool started: false
    property bool finishing: false
    property var residentBefore: null
    property var keptBefore: null
    property var multiBefore: null
    property string firstQueueResult: ""
    property string secondQueueResult: ""
    property string menuResult: ""
    property string toggleResult: ""
    property string closeResult: ""

    QtObject {
        id: shellConfig
        property var config: ({ version: 1, bar: { id: "aurelia.bar" } })
    }

    QtObject {
        id: shellApi
    }

    QtObject {
        id: fakeRegistry
        property QtObject shellConfig: shellConfig
        property string packageRoot: Qt.resolvedUrl(".")
        property int registryRevision: 1
        property int runtimeFailureRevision: 0
        property var runtimeFailures: ({})
        property var installedPlugins: ({
            "fixture.resident": {
                name: "Resident service",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["service"],
                entryPoints: { service: "ResidentService.qml" },
                keepLoaded: true
            },
            "fixture.kept": {
                name: "Kept panel",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "KeptPanel.qml" },
                keepLoaded: true
            },
            "fixture.queue": {
                name: "Queue panel",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "QueuePanel.qml" },
                keepLoaded: false
            },
            "fixture.lazy": {
                name: "Lazy panel",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["panel"],
                entryPoints: { panel: "LazyPanel.qml" },
                keepLoaded: false
            },
            "fixture.multi": {
                name: "Multi-kind service widget",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["service", "bar-widget"],
                entryPoints: { service: "MultiService.qml", barWidget: "MultiWidget.qml" },
                keepLoaded: true
            },
            "fixture.menu-widget": {
                name: "Menu widget",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["menu", "bar-widget"],
                entryPoints: { menu: "MenuPanel.qml", barWidget: "MultiWidget.qml" },
                keepLoaded: false
            }
        })
        property var pluginIds: [
            "fixture.kept",
            "fixture.lazy",
            "fixture.menu-widget",
            "fixture.multi",
            "fixture.queue",
            "fixture.resident"
        ]

        signal pluginsChanged()
        signal pluginFailureRecorded(string pluginId, string kind, string phase, string sourcePath, string entryPoint, string detail)

        function isKnown(id) {
            return installedPlugins[id] !== undefined
        }

        function isEnabled(id) {
            return isKnown(id)
        }

        function primaryKind(id) {
            if (!isKnown(id)) return ""
            return installedPlugins[id].kinds.indexOf("service") !== -1
                ? "service" : installedPlugins[id].kinds[0]
        }

        function entryPointUrl(id, kind) {
            if (!isKnown(id)) return ""
            var key = kind === "bar-widget" ? "barWidget" : kind
            var value = installedPlugins[id].entryPoints[key]
            return value ? Qt.resolvedUrl(value) : ""
        }

        function boundedFailureDetail(value) {
            return String(value || "plugin failure").substring(0, 512)
        }

        function hasActiveRuntimeFailure(id, kind) {
            var revision = runtimeFailureRevision
            return false
        }

        function recordRuntimeFailure(id, kind, phase, sourcePath, entryPoint, detail) {
            return true
        }

        function clearRuntimeFailure(id, kind) {
            return false
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
                    keepLoaded: installedPlugins[id].keepLoaded === true,
                    failures: []
                })
            }
            return result
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

    Loader {
        id: barRegistryLoader
        source: root.barRegistrySource
        onLoaded: {
            item.pluginRegistry = fakeRegistry
            item.sync()
        }
    }

    IpcHandler {
        target: "aurelia-lifecycle-fixture"
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

    function start() {
        if (root.started || !hostLoader.item || !barRegistryLoader.item) return
        root.started = true
        var host = hostLoader.item
        root.residentBefore = host.itemFor("fixture.resident")
        root.keptBefore = host.itemFor("fixture.kept")
        root.multiBefore = host.itemFor("fixture.multi")

        host.beginReload()
        host.finishReload()

        host.beginReload({ "fixture.queue": true })
        root.firstQueueResult = host.open("fixture.queue", "one")
        root.secondQueueResult = host.open("fixture.queue", "two")
        host.finishReload()

        root.menuResult = host.open("fixture.menu-widget", "{}")
        root.toggleResult = host.toggle("fixture.kept", "{}")
        root.closeResult = host.close("fixture.kept")
        host.open("fixture.lazy", "{}")
        afterLifecycle.start()
    }

    function finish() {
        if (root.finishing || !hostLoader.item || !barRegistryLoader.item) return
        root.finishing = true
        var host = hostLoader.item
        var queue = host.itemFor("fixture.queue")
        var menu = host.itemFor("fixture.menu-widget")
        var multi = host.itemFor("fixture.multi")
        var queuePayloads = queue && Array.isArray(queue.received) ? queue.received : []
        var multiService = multi && typeof multi.health === "function" ? multi.health("{}") : ""
        var keptAfter = host.itemFor("fixture.kept")
        var residentAfter = host.itemFor("fixture.resident")
        resultFile.setText(JSON.stringify({
            hostAlive: hostLoader.item !== null,
            pingResponded: hostLoader.item !== null,
            residentPreserved: residentAfter === root.residentBefore,
            keptPreserved: keptAfter === root.keptBefore,
            multiServicePreserved: multi === root.multiBefore && multiService === "multi-service",
            multiWidgetRegistered: barRegistryLoader.item.hasWidget("fixture.multi"),
            menuWidgetRegistered: barRegistryLoader.item.hasWidget("fixture.menu-widget"),
            menuLoaded: menu !== null,
            menuResult: root.menuResult,
            queueFirstResult: root.firstQueueResult,
            queueSecondResult: root.secondQueueResult,
            queuePayloadsInOrder: JSON.stringify(queuePayloads) === JSON.stringify(["one", "two"]),
            toggleResult: root.toggleResult,
            closeResult: root.closeResult,
            lazyUnloaded: host.itemFor("fixture.lazy") === null,
            loadedEventAvailable: typeof host.pluginLoaded === "function",
            reloadEventAvailable: typeof host.pluginReloaded === "function"
        }) + "\n")
    }

    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: root.start()
    }

    Timer {
        id: afterLifecycle
        interval: 700
        repeat: false
        onTriggered: {
            if (!hostLoader.item) return
            var queue = hostLoader.item.itemFor("fixture.queue")
            if (!queue || !Array.isArray(queue.received) || queue.received.length < 2) {
                afterLifecycle.restart()
                return
            }
            hostLoader.item.close("fixture.lazy")
            unloadCheck.start()
        }
    }

    Timer {
        id: unloadCheck
        interval: 400
        repeat: false
        onTriggered: root.finish()
    }

    Timer {
        interval: 7000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
