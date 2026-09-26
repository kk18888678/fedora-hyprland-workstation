import QtQuick
import Quickshell
import Quickshell.Io

// Disposable fixture for the screenshot capability independence property.
//
// The fake registry reports `aurelia.screenshot` as known but disabled and
// mounts no plugin instances, so no bar widget slot and no plugin instance is
// ever created. A real PluginHost is used so `pluginHost.call` follows the
// genuine `callBarWidget` -> "not-loaded" path. The real core ShellCallRouter
// and ScreenshotService are then asked to serve `shell call
// aurelia.screenshot`, proving the shortcut capability survives plugin
// disable and removal from the bar layout.
ShellRoot {
    id: root

    readonly property string resultPath: Quickshell.env("AURELIA_SCREENSHOT_INDEPENDENCE_RESULT") || ""
    readonly property string hostSource: Quickshell.env("AURELIA_SCREENSHOT_HOST_SOURCE") || ""
    readonly property string routerSource: Quickshell.env("AURELIA_SCREENSHOT_ROUTER_SOURCE") || ""
    readonly property string serviceSource: Quickshell.env("AURELIA_SCREENSHOT_SERVICE_SOURCE") || ""
    readonly property string shellRoot: Quickshell.env("AURELIA_SCREENSHOT_SHELL_ROOT") || ""

    property bool finishing: false
    property double startedAt: Date.now()
    property string pluginCallResult: ""
    property string quickScreenResult: ""
    property string pingResult: ""
    property string quickRegionResult: ""
    property string isVisibleResult: ""
    property string unboundResult: ""
    property string capturedMode: ""
    property int capturedCount: 0
    property string regionStage: ""

    QtObject {
        id: fakeShellConfig

        property var config: ({
            version: 1,
            bar: { id: "aurelia.bar", position: "top", layout: { left: [], center: [], right: [] } }
        })

        // The screenshot plugin is explicitly disabled and absent from every
        // bar.layout section.
        function isPluginEnabled(id, firstParty) { return false }
        function settingsForEntry(instanceId, selector) { return ({}) }
    }

    QtObject {
        id: fakeShellApi

        property var published: []

        function call(target, method, argument) {
            if (String(target) === "aurelia.notifications" &&
                String(method) === "publishScreenshot") {
                var next = published.slice()
                next.push(String(argument))
                published = next
                return "ok"
            }
            return "not-loaded"
        }
    }

    QtObject {
        id: fakeRegistry

        property QtObject shellConfig: fakeShellConfig
        property int registryRevision: 1
        property int runtimeFailureRevision: 0
        property var runtimeFailures: ({})
        property var failureHistory: ({})
        // No plugin is mounted. The screenshot plugin exists in the catalog
        // with its bar-widget metadata and entry point intact.
        property var pluginIds: []
        property var installedPlugins: ({
            "aurelia.screenshot": {
                name: "Screenshots",
                version: "1.0.0",
                description: "Fixture",
                kinds: ["bar-widget"],
                entryPoints: { barWidget: "ui/ScreenshotBarWidget.qml" },
                barWidget: {
                    displayName: "Screenshots",
                    category: "System",
                    allowMultiple: false,
                    defaultSection: "center"
                },
                __isFirstParty: true
            }
        })

        signal pluginsChanged()
        signal localPluginChanged(string changedPluginId)
        signal pluginFailureRecorded(string pluginId, string kind, string phase, string sourcePath, string entryPoint, string detail)

        function isKnown(id) { return installedPlugins[id] !== undefined }
        function isEnabled(id) { return false }
        function primaryKind(id) { return isKnown(id) ? installedPlugins[id].kinds[0] : "" }
        function resolveEnabledId(id) { return String(id || "") }
        function hasActiveRuntimeFailure(id, kind) { return false }
        function recordRuntimeFailure(id, kind, phase, sourcePath, entryPoint, detail) { return false }
        function clearRuntimeFailure(id, kind) { return false }
        function sourceDescriptor(id, kind) {
            return { valid: false, id: id, kind: kind, url: "", error: "fixture: plugins are not mounted" }
        }
        function pluginSummaries() { return [] }
    }

    Loader {
        id: hostLoader
        source: root.hostSource
        onLoaded: {
            item.registry = fakeRegistry
            item.shellApi = fakeShellApi
            item.appLibrary = fakeShellApi
        }
    }

    Loader {
        id: routerLoader
        source: root.routerSource
    }

    Loader {
        id: serviceLoader
        source: root.serviceSource
    }

    function wire() {
        if (!hostLoader.item || !routerLoader.item || !serviceLoader.item) return false
        serviceLoader.item.shell = fakeShellApi
        serviceLoader.item.pluginHost = hostLoader.item
        serviceLoader.item.aureliaPath = root.shellRoot
        serviceLoader.item.testMode = true
        routerLoader.item.screenshotService = serviceLoader.item
        return true
    }

    function exercise() {
        if (root.finishing) return
        var host = hostLoader.item
        var router = routerLoader.item
        // The disabled plugin still registers no bar widget slot, so the plain
        // plugin path is genuinely broken.
        root.pluginCallResult = host.call("aurelia.screenshot", "quickScreen", "{}")
        root.pingResult = router.call(host, "aurelia.screenshot", "ping", "")
        root.quickScreenResult = router.call(host, "aurelia.screenshot", "quickScreen", "{}")
        root.unboundResult = router.call(host, "aurelia.screenshot", "doesNotExist", "")
        captureCheck.start()
    }

    function checkCapture() {
        if (root.finishing) return
        var service = serviceLoader.item
        root.capturedMode = service.lastCaptureRequest.mode
        root.capturedCount = service.captureCount
        var router = routerLoader.item
        root.quickRegionResult = router.call(hostLoader.item, "aurelia.screenshot", "quickRegion", "")
        root.regionStage = service.controller.captureStage
        root.isVisibleResult = router.call(hostLoader.item, "aurelia.screenshot", "isVisible", "")
        root.finish()
    }

    function finish() {
        if (root.finishing || root.resultPath === "") return
        root.finishing = true
        resultFile.setText(JSON.stringify({
            hostLoaded: hostLoader.item !== null,
            routerLoaded: routerLoader.item !== null,
            serviceLoaded: serviceLoader.item !== null,
            hostStatus: hostLoader.status,
            routerStatus: routerLoader.status,
            serviceStatus: serviceLoader.status,
            pluginKnown: fakeRegistry.isKnown("aurelia.screenshot") === true,
            pluginDisabled: fakeRegistry.isEnabled("aurelia.screenshot") === false,
            barLayoutEmpty: fakeShellConfig.config.bar.layout.left.length === 0 &&
                fakeShellConfig.config.bar.layout.center.length === 0 &&
                fakeShellConfig.config.bar.layout.right.length === 0,
            pluginCallResult: root.pluginCallResult,
            quickScreenResult: root.quickScreenResult,
            routerReachedCore: root.quickScreenResult === "started",
            pingResult: root.pingResult,
            unboundResult: root.unboundResult,
            capturedMode: root.capturedMode,
            capturedCount: root.capturedCount,
            captureStartable: root.capturedMode === "full" && root.capturedCount >= 1,
            quickRegionResult: root.quickRegionResult,
            regionStage: root.regionStage,
            isVisibleResult: root.isVisibleResult,
            diagnostic: serviceLoader.item ? serviceLoader.item.lastDiagnostic : ""
        }) + "\n")
    }

    IpcHandler {
        id: fixtureIpc
        target: "aurelia-screenshot-independence-fixture"

        function ping(): string { return "ok" }
    }

    FileView {
        id: resultFile
        path: root.resultPath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: false
        printErrors: true
        onSaved: Qt.quit()
        onSaveFailed: Qt.quit()
    }

    Timer {
        id: readinessTimer
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (root.wire()) {
                readinessTimer.stop()
                root.exercise()
            } else if (Date.now() - root.startedAt > 5000) {
                readinessTimer.stop()
                root.pluginCallResult = "not-wired"
                root.finish()
            }
        }
    }

    Timer {
        id: captureCheck
        interval: 600
        repeat: false
        onTriggered: root.checkCapture()
    }

    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
