import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// T41 bar fixture. The actual Bar.qml is loaded with a minimal in-memory
// configuration and a fake healthy widget; all state is redirected to the
// test's temporary XDG state directory.
ShellRoot {
    id: root

    readonly property string barSource: Quickshell.env("AURELIA_BAR_HIDING_SOURCE") || ""
    readonly property string resultPath: Quickshell.env("AURELIA_BAR_HIDING_RESULT") || ""
    readonly property string writerPath: Quickshell.env("AURELIA_BAR_HIDING_WRITER") || ""
    property var bar: null
    property bool evaluated: false
    property string widgetBefore: ""
    property string widgetAfter: ""
    property bool writerFailureReported: false

    QtObject {
        id: fakeConfig
        property var config: ({
            version: 1,
            bar: {
                id: "aurelia.bar",
                position: "top",
                transparent: false,
                centerAnchor: "",
                layout: {left: [], center: [], right: []}
            }
        })
        function defaultBarConfig() { return config.bar }
    }

    QtObject {
        id: fakeRegistry
        property int registryRevision: 1
        property var runtimeFailures: ({})
        function isKnown(id) { return id === "healthy.widget" }
        function isEnabled(id) { return id === "healthy.widget" }
        function primaryKind(id) { return id === "healthy.widget" ? "bar-widget" : "" }
        function metadataFor(id) { return id === "healthy.widget" ? {displayName: "Healthy"} : null }
    }

    QtObject {
        id: fakeHost
        function activeBar() { return root.bar }
    }

    QtObject {
        id: healthyWidget
        property string pluginId: "healthy.widget"
        property string instanceId: "healthy.widget"
        property var widgetItem: healthyWidget
        function invoke(method, argument) { return method === "health" ? "healthy" : "" }
    }

    Loader {
        id: barLoader
        source: root.barSource
        onLoaded: {
            item.shell = ({})
            item.shellConfig = fakeConfig
            item.pluginRegistry = fakeRegistry
            item.barWidgetRegistry = fakeRegistry
            item.pluginHost = fakeHost
            item.hiddenStatePathOverride = Quickshell.env("AURELIA_BAR_HIDING_STATE") || ""
            item.widgetSlots = [healthyWidget]
            root.bar = item
        }
    }

    Process {
        id: writerProcess
        command: root.writerPath === "" ? [] : [root.writerPath, "on"]
        running: false
        onExited: function(code) {
            if (code !== 0) root.writerFailureReported = true
            root.hiddenTimer.start()
        }
    }

    Process {
        id: restoreProcess
        command: root.writerPath === "" ? [] : [root.writerPath, "off"]
        running: false
        onExited: function(code) {
            if (code !== 0) root.writerFailureReported = true
            root.restoreTimer.start()
        }
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

    function widgetHealth() {
        return root.bar ? root.bar.callWidget("healthy.widget", "health", "") : "missing"
    }

    function surface() {
        return root.bar && Array.isArray(root.bar.barPanels) && root.bar.barPanels.length > 0
            ? root.bar.barPanels[0] : null
    }

    function finish() {
        if (root.evaluated || !root.bar) return
        root.evaluated = true
        resultFile.setText(JSON.stringify({
            loaded: true,
            initialVisible: root.initialVisible,
            hidden: root.hidden,
            hiddenVisible: root.hiddenVisible,
            hiddenExclusion: root.hiddenExclusion,
            hiddenOffscreen: root.hiddenOffscreen,
            restored: root.restored,
            restoredExclusion: root.restoredExclusion,
            widgetBefore: root.widgetBefore,
            widgetAfter: root.widgetAfter,
            writerFailureReported: root.writerFailureReported
        }) + "\n")
    }

    property bool initialVisible: false
    property bool hidden: false
    property bool hiddenVisible: false
    property bool hiddenExclusion: false
    property bool hiddenOffscreen: false
    property bool restored: false
    property bool restoredExclusion: false

    Timer {
        id: startTimer
        interval: 500
        running: true
        repeat: false
        onTriggered: {
            if (!root.bar || !root.surface()) { restart(); return }
            root.initialVisible = root.surface().visible === true
            root.widgetBefore = root.widgetHealth()
            if (!writerProcess.running) writerProcess.running = true
        }
    }

    Timer {
        id: hiddenTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (!root.bar || !root.surface() || root.bar.barHidden !== true) { restart(); return }
            root.hidden = true
            root.hiddenVisible = root.surface().visible === true
            root.hiddenExclusion = root.surface().exclusionMode === ExclusionMode.Ignore
            root.hiddenOffscreen = root.surface().margins.top < 0
            root.widgetAfter = root.widgetHealth()
            if (!restoreProcess.running) restoreProcess.running = true
        }
    }

    Timer {
        id: restoreTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (!root.bar || !root.surface() || root.bar.barHidden === true) { restart(); return }
            root.restored = true
            root.restoredExclusion = root.surface().exclusionMode === ExclusionMode.Auto
            root.finish()
        }
    }

    Timer {
        interval: 12000
        running: true
        repeat: false
        onTriggered: Qt.quit()
    }
}
